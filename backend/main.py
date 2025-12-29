import base64
import tempfile
import os
from datetime import datetime  # timestamps

from fastapi import FastAPI, WebSocket, WebSocketDisconnect  # API / WS
from fastapi.middleware.cors import CORSMiddleware  # CORS handling
from ai.speech_translation import translate_json_list  # text translation

# from db.connection import db  # MongoDB client (currently unused)

# from pymongo import MongoClient  # raw Mongo client (unused)
from ai.speech_detection import detect_language_and_transcribe_from_base64  # STT
from gtts import gTTS  # TTS generation

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # allow all origins (dev-friendly; tighten in prod)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

last_source_lang = None
last_target_lang = None

# Language code mapping (ISO-639-1)
LANG_MAP = {
    "ko": "ko",  # Korean
    "en": "en",  # English
    "ja": "ja",  # Japanese
    "zh": "zh-CN",  # Chinese
    "es": "es",  # Spanish
}

# Read translated texts with gTTS
def generate_tts(text, lang="en"):
    """Generate Google TTS audio as base64 for a given text/lang."""
    lang_code = LANG_MAP.get(lang, "en")  # Fallback to en if an input lang is unsupported
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
    """WebSocket for speech STT → translate → TTS, with simple turn-taking."""

    global last_source_lang, last_target_lang
    await websocket.accept()
    print("WebSocket connected for speech detection.")

    speaker_id = 1

    try:
        while True:
            data = await websocket.receive_json()
            command = data.get("command")

            if command == "transcribe":
                # Receive audio + desired target language from client
                audio_b64 = data.get("audio")
                incoming_target_lang = data.get("target_lang1")

                try:
                    # 1) STT + language detection
                    result = detect_language_and_transcribe_from_base64(audio_b64)
                    source_lang = result["language"]
                    text = result["text"]
                    emotion = result["emotion"]
                    scores = result["scores"]

                    current_speaker = f"Speaker {speaker_id}"

                    if speaker_id == 1:
                        # Speaker 1: translate to requested target
                        target_lang = incoming_target_lang
                        last_source_lang = source_lang
                        last_target_lang = target_lang
                    else:
                        # Speaker 2: reply in the previous speaker's language
                        target_lang = last_source_lang
                        source_lang = last_target_lang

                    # 2) Translate recognized text
                    translated = (await translate_json_list(
                        [
                            {
                                "timestamp": datetime.utcnow().isoformat(),
                                "lang": source_lang,
                                "text": text,
                            }
                        ],
                        target_lang=target_lang,
                    ))[0]

                    # 3) Generate TTS for translated text
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

@app.get("/")
def root():
    return {"message": "FastAPI minimal test successful."}
