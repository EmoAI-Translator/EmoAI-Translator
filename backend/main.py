import base64
import tempfile

# import cv2
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
from gtts import gTTS
import base64
import tempfile
import os

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

last_source_lang = None
last_target_lang = None

# 언어 코드 매핑 (ISO-639-1 기준)
LANG_MAP = {
    "ko": "ko",  # 한국어
    "en": "en",  # 영어
    "ja": "ja",  # 일본어
    "zh": "zh-CN",  # 중국어
    "es": "es",  # 스페인어
}


def generate_tts(text, lang="en"):
    """
    주어진 텍스트와 언어에 맞는 Google TTS 음성을 base64로 반환
    """
    lang_code = LANG_MAP.get(lang, "en")  # 지원하지 않는 언어면 영어로 fallback
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
        tts = gTTS(text=text, lang=lang_code)
        tts.save(f.name)
        f.seek(0)
        audio_bytes = f.read()

    audio_b64 = base64.b64encode(audio_bytes).decode("utf-8")
    os.remove(f.name)
    return audio_b64


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
            "tts_audio_b64": "<base64_encoded_tts_audio_string>"
        },
        "emotion": "happy",
        "emotion_scores": {"happy": 0.95, "sad": 0.02, ...}
    }
    """

    global last_source_lang, last_target_lang
    await websocket.accept()
    print("WebSocket connected for speech detection.")

    speaker_id = 1

    try:
        while True:
            data = await websocket.receive_json()
            command = data.get("command")

            if command == "transcribe":
                audio_b64 = data.get("audio")
                incoming_target_lang = data.get("target_lang")

                try:
                    result = detect_language_and_transcribe_from_base64(audio_b64)
                    source_lang = result["language"]
                    text = result["text"]
                    emotion = result["emotion"]
                    scores = result["scores"]

                    current_speaker = f"Speaker {speaker_id}"

                    if speaker_id == 1:
                        target_lang = incoming_target_lang or "en"
                        last_source_lang = source_lang
                        last_target_lang = target_lang
                    else:
                        target_lang = last_source_lang if last_source_lang else "ko"
                        source_lang = last_target_lang if last_target_lang else "en"

                    translated = translate_json_list(
                        [
                            {
                                "timestamp": datetime.utcnow().isoformat(),
                                "lang": source_lang,
                                "text": text,
                            }
                        ],
                        target_lang=target_lang,
                    )[0]

                    translated_payload = {
                        "timestamp": translated.get("timestamp"),
                        "lang": target_lang,
                        "text": translated.get("translated_text"),
                        "tts_audio_b64": generate_tts(
                            translated.get("translated_text"), lang=target_lang
                        ),
                    }

                    await websocket.send_json(
                        {
                            "status": "success",
                            "type": "speech",
                            "speaker": current_speaker,
                            "original": {"lang": source_lang, "text": text},
                            "translated": translated_payload,
                            "emotion": emotion,
                            "emotion_scores": scores,
                        }
                    )

                    speaker_id = 2 if speaker_id == 1 else 1

                except Exception as e:
                    await websocket.send_json({"status": "error", "message": str(e)})

            else:
                await websocket.send_json(
                    {"status": "error", "message": "Unknown command."}
                )

    except WebSocketDisconnect:
        print("Speech WebSocket disconnected.")


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


@app.get("/")
def root():
    return {"message": "FastAPI minimal test successful."}


# MongoDB Connection
client = MongoClient(os.getenv("MONGO_URI"))
db = client[os.getenv("DB_NAME")]
emotions_collection = db["emotions"]


@app.get("/emotions")
def get_emotions():
    emotions = list(emotions_collection.find())
    for e in emotions:
        e["_id"] = str(e["_id"])
    return emotions


# websocket endpoint for real-time emotion detection and collection, json responses.
# @app.websocket("/ws/emotion")
# async def emotion_websocket(websocket: WebSocket):
#     await websocket.accept()
#     print("WebSocket connected for emotion detection.")

#     global collecting

#     try:
#         while True:
#             data = await websocket.receive_json()
#             command = data.get("command")

#             if command == "detect":
#                 try:
#                     image_b64 = data.get("frame")
#                     image_data = base64.b64decode(image_b64)
#                     np_arr = np.frombuffer(image_data, np.uint8)
#                     frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

#                     emotion = detect_emotion(frame)

#                     if collecting:
#                         emotion_buffer.append(emotion)

#                     await websocket.send_json(
#                         {
#                             "status": "success",
#                             "type": "realtime",
#                             "emotion": emotion,
#                             "collecting": collecting,
#                         }
#                     )
#                 except Exception as e:
#                     await websocket.send_json({"status": "error", "message": str(e)})

#             elif command == "start_collect":
#                 if collecting:
#                     await websocket.send_json(
#                         {"status": "error", "message": "Already collecting emotions."}
#                     )
#                     continue

#                 duration = data.get("duration", 5)
#                 emotion_buffer.clear()
#                 collecting = True

#                 await websocket.send_json(
#                     {"status": "started", "type": "collection", "duration": duration}
#                 )

#                 async def stop_and_return():
#                     await asyncio.sleep(duration)
#                     global collecting
#                     collecting = False
#                     result = get_average_emotion()

#                     # Save summary to MongoDB
#                     try:
#                         summary_doc = {
#                             "status": "success",
#                             "type": "summary",
#                             "dominant_emotion": result.get("dominant_emotion"),
#                             "emotion_distribution": result.get("emotion_distribution"),
#                             "sample_count": result.get("sample_count"),
#                             "timestamp": datetime.utcnow().isoformat(),
#                         }

#                         result_db = emotions_collection.insert_one(summary_doc)
#                         print(f"Summary saved to MongoDB (ID: {result_db.inserted_id})")

#                     except Exception as db_error:
#                         print("MongoDB summary insert failed:", db_error)

#                     await websocket.send_json(
#                         {"status": "success", "type": "summary", "data": result}
#                     )

#                 asyncio.create_task(stop_and_return())

#             else:
#                 await websocket.send_json(
#                     {"status": "error", "message": "Unknown command."}
#                 )

#     except WebSocketDisconnect:
#         print("WebSocket disconnected.")
