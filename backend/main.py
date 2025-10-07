from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from ai.emotion_detection import start_collection, get_average_emotion

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.post("/start-emotion")
def start_emotion_collection():
    start_collection()
    return {"message": "Emotion collection started for 5 seconds."}


@app.get("/emotion-result")
def get_emotion_result():
    result = get_average_emotion()
    return result
