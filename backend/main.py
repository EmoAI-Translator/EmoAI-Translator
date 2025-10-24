import base64
import cv2
import numpy as np
import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from ai.speech_translation import translate_json_list
from db.connection import db
from pydantic import BaseModel
from pymongo import MongoClient
from datetime import datetime
import os
from bson import ObjectId
from fastapi import Body
from ai.emotion_detection import (
    detect_emotion,
    emotion_buffer,
    collecting,
    get_average_emotion,
)
from ai.speech_detection import detect_language_and_transcribe_from_base64

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root():
    return {"message": "FastAPI minimal test successful."}


# MongoDB Connection
client = MongoClient(os.getenv("MONGO_URI"))
db = client[os.getenv("DB_NAME")]
emotions_collection = db["emotions"]


@app.post("/save_emotion")
async def save_emotion(payload: dict = Body(...)):
    """Receive WebSocket-style JSON and save it to MongoDB"""
    try:
        # Add timestamp if not included
        if "timestamp" not in payload:
            from datetime import datetime

            payload["timestamp"] = datetime.utcnow().isoformat()

        # Insert JSON as-is
        result = emotions_collection.insert_one(payload)

        print("MongoDB insert result:", result.inserted_id)
        # Return confirmation
        return {
            "status": "success",
            "inserted_id": str(result.inserted_id),
            "saved_data": payload,
        }

    except Exception as e:
        print("MongoDB insert error:", e)
        return {"status": "error", "message": str(e)}


@app.get("/emotions")
def get_emotions():
    emotions = list(emotions_collection.find())
    for e in emotions:
        e["_id"] = str(e["_id"])
    return emotions


# websocket endpoint for real-time emotion detection and collection, json responses.
@app.websocket("/ws/emotion")
async def emotion_websocket(websocket: WebSocket):
    await websocket.accept()
    print("WebSocket connected for emotion detection.")

    global collecting

    try:
        while True:
            data = await websocket.receive_json()
            command = data.get("command")

            if command == "detect":
                try:
                    image_b64 = data.get("frame")
                    image_data = base64.b64decode(image_b64)
                    np_arr = np.frombuffer(image_data, np.uint8)
                    frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

                    emotion = detect_emotion(frame)

                    if collecting:
                        emotion_buffer.append(emotion)

                    await websocket.send_json(
                        {
                            "status": "success",
                            "type": "realtime",
                            "emotion": emotion,
                            "collecting": collecting,
                        }
                    )
                except Exception as e:
                    await websocket.send_json({"status": "error", "message": str(e)})

            elif command == "start_collect":
                if collecting:
                    await websocket.send_json(
                        {"status": "error", "message": "Already collecting emotions."}
                    )
                    continue

                duration = data.get("duration", 5)
                emotion_buffer.clear()
                collecting = True

                await websocket.send_json(
                    {"status": "started", "type": "collection", "duration": duration}
                )

                async def stop_and_return():
                    await asyncio.sleep(duration)
                    global collecting
                    collecting = False
                    result = get_average_emotion()

                    # Save summary to MongoDB
                    try:
                        summary_doc = {
                            "status": "success",
                            "type": "summary",
                            "dominant_emotion": result.get("dominant_emotion"),
                            "emotion_distribution": result.get("emotion_distribution"),
                            "sample_count": result.get("sample_count"),
                            "timestamp": datetime.utcnow().isoformat(),
                        }

                        result_db = emotions_collection.insert_one(summary_doc)
                        print(f"Summary saved to MongoDB (ID: {result_db.inserted_id})")

                    except Exception as db_error:
                        print("MongoDB summary insert failed:", db_error)

                    await websocket.send_json(
                        {"status": "success", "type": "summary", "data": result}
                    )

                asyncio.create_task(stop_and_return())

            else:
                await websocket.send_json(
                    {"status": "error", "message": "Unknown command."}
                )

    except WebSocketDisconnect:
        print("WebSocket disconnected.")


@app.websocket("/ws/speech")
async def speech_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for real-time speech recognition and translation.
    Alternates speakers automatically based on each speech turn.

    Input Example (Frontend → Backend)
    {
        "command": "transcribe",
        "audio": "<base64_encoded_audio_string>",
        "target_lang": "en"
    }

    Return Example (Backend → Frontend)
    {
        "status": "success",
        "type": "speech",
        "speaker": "Speaker 1",
        "original": {
            "lang": "ko",
            "text": "안녕하세요"
        },
        "translated": {
            "timestamp": datetime.utcnow().isoformat(),
            "lang": lang,
            "text": text,
        },
        "emotion": "happy",
        "emotion_scores": {"happy": 0.95, "sad": 0.02, ...}
    }
    """

    await websocket.accept()
    print("WebSocket connected for speech detection.")

    # Initialize speaker alternation state (turn-based)
    speaker_id = 1

    try:
        while True:
            data = await websocket.receive_json()
            command = data.get("command")

            if command == "transcribe":
                audio_b64 = data.get("audio")
                target_lang = data.get("target_lang", "ko")

                try:
                    # Step 1. Transcribe and detect language from audio
                    result = detect_language_and_transcribe_from_base64(audio_b64)
                    lang = result["language"]
                    text = result["text"]
                    emotion = result["emotion"]
                    scores = result["scores"]

                    # Step 2. Assign current speaker (turn-based alternation)
                    current_speaker = f"Speaker {speaker_id}"

                    # Step 3. Translate recognized speech
                    translated = translate_json_list(
                        [
                            {
                                "timestamp": datetime.utcnow().isoformat(),
                                "lang": lang,
                                "text": text,
                            }
                        ],
                        target_lang=target_lang,
                    )[0]

                    # translate_json_list currently returns {
                    #   'timestamp': ..., 'original_text': ..., 'translated_text': ...
                    # }
                    # Frontend expects translated to contain 'timestamp', 'lang', 'text'.
                    # Map the translator output to the frontend-expected shape here.
                    try:
                        translated_payload = {
                            "timestamp": translated.get("timestamp"),
                            "lang": target_lang,
                            # prefer the key 'text' for frontend; fall back to translated_text or original_text
                            "text": translated.get("translated_text")
                            or translated.get("text")
                            or translated.get("original_text"),
                        };
                    except Exception:
                        translated_payload = {
                            "timestamp": datetime.utcnow().isoformat(),
                            "lang": target_lang,
                            "text": None,
                        }

                    # Step 4. Send full JSON response including speaker info
                    await websocket.send_json(
                        {
                            "status": "success",
                            "type": "speech",
                            "speaker": current_speaker,
                            "original": {"lang": lang, "text": text},
                            "translated": translated,
                            "emotion": emotion,
                            "emotion_scores": scores,
                        }
                    )

                    # Alternate speaker automatically for next turn
                    speaker_id = 2 if speaker_id == 1 else 1

                except Exception as e:
                    await websocket.send_json({"status": "error", "message": str(e)})

            else:
                await websocket.send_json(
                    {"status": "error", "message": "Unknown command."}
                )

    except WebSocketDisconnect:
        print("Speech WebSocket disconnected.")
