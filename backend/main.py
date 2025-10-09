import base64
import cv2
import numpy as np
import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
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
    return {"message": "✅ FastAPI minimal test successful."}

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
            "saved_data": payload
        }

    except Exception as e:
        print("❌ MongoDB insert error:", e)
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
    print("📡 WebSocket connected for emotion detection.")

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
                            "timestamp": datetime.utcnow().isoformat()
                        }

                        result_db = emotions_collection.insert_one(summary_doc)
                        print(f"💾 Summary saved to MongoDB (ID: {result_db.inserted_id})")

                    except Exception as db_error:
                        print("⚠️ MongoDB summary insert failed:", db_error)

                    await websocket.send_json(
                        {"status": "success", "type": "summary", "data": result}
                    )

                asyncio.create_task(stop_and_return())

            else:
                await websocket.send_json(
                    {"status": "error", "message": "Unknown command."}
                )

    except WebSocketDisconnect:
        print("❌ WebSocket disconnected.")