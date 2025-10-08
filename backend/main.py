import base64
import cv2
import numpy as np
import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
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
