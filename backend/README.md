# Backend (FastAPI)

The backend handles speech transcription, translation, emotion detection, and optional TTS generation. It exposes a WebSocket endpoint used by the Flutter frontend and a few HTTP helpers.

## Tech stack
- **API**: FastAPI
- **AI**: DeepFace (emotion detection), Google Translate (text translation), gTTS (optional TTS)
- **Optional DB**: MongoDB (commented out/unused)

## Requirements
- Python 3.10+
- `ffmpeg` installed and available on `PATH` (used for audio conversions)
- (Optional) `shape_predictor_68_face_landmarks.dat` model

## Setup
```bash
cd backend
python -m venv .venv         # optional
source .venv/bin/activate
pip install -r requirements.txt
```

## Running
Start the server in development mode:
```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

This will expose:
- WebSocket: `ws://<host>:8000/ws/speech` – frontend sends base64 audio and receives JSON responses with transcription, translation, emotion, and optional TTS audio.
- HTTP POST `/save_emotion` – stub for saving emotion data (currently no-op)

Custom configuration (e.g. model paths or port) can be adjusted directly in `main.py` or by environment variables if you extend the code.

## Code pointers
- **`ai/speech_detection.py`** – language detection & transcription logic
- **`ai/speech_translation.py`** – integration with Google Translate
- **`ai/tone_emotion_detection.py`** – emotion scoring using DeepFace
- **`main.py`** – WebSocket handlers and helper functions

## Notes
- Audio arriving from the frontend is normalized to 16kHz mono OPUS using ffmpeg before processing.
- The WebSocket handler alternates speaker IDs automatically.

Contributions and feature ideas are welcome!