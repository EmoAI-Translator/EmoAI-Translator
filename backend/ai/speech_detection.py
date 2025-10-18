import base64
import queue
import threading
import time
from datetime import datetime
import speech_recognition as sr
import tempfile
import os
import whisper
from ai.speech_translation import translate_json_list
import warnings

warnings.filterwarnings(
    "ignore", message="FP16 is not supported on CPU; using FP32 instead"
)

# Load Whisper model once
whisper_model = whisper.load_model("base")


def detect_language_and_transcribe_from_base64(audio_b64: str):
    """Decode base64 WAV, transcribe, detect language."""
    audio_bytes = base64.b64decode(audio_b64)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_wav:
        temp_wav.write(audio_bytes)
        temp_path = temp_wav.name

    try:
        result = whisper_model.transcribe(temp_path)
    finally:
        os.remove(temp_path)

    language = result.get("language", "unknown")
    text = result.get("text", "").strip()
    return {"language": language, "text": text}


def live_turn_taking_recognition():
    """
    Real-time microphone recognition with Whisper-based language detection.
    Detects turns based on silence (no fixed phrase_time_limit).
    Alternates speakers automatically: Speaker 1 <-> Speaker 2
    """
    r = sr.Recognizer()

    try:
        mic = sr.Microphone()
    except Exception as e:
        print("Microphone not found or cannot be opened:", e)
        raise

    # Adjust for ambient noise once before starting
    with mic as source:
        print("Adjusting for ambient noise...")
        r.adjust_for_ambient_noise(source, duration=1.0)
        print(f"Done. Energy threshold: {r.energy_threshold}")

    stop_flag = threading.Event()
    recognized_results = []

    def recognize_loop():
        speaker_id = 1
        print("🎤 Listening... Speak into your microphone. (Ctrl+C to stop)")

        while not stop_flag.is_set():
            with mic as source:
                try:
                    print(
                        f"\n🗣️  Speaker {speaker_id} speaking... (will stop on silence)"
                    )
                    # r.listen() automatically stops on silence if phrase_time_limit is None
                    audio = r.listen(source, timeout=None)
                except Exception as inner_e:
                    print("Recording error:", inner_e)
                    continue

            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

            try:
                # Convert AudioData → WAV → base64
                with tempfile.NamedTemporaryFile(
                    delete=False, suffix=".wav"
                ) as temp_audio:
                    temp_audio.write(audio.get_wav_data())
                    temp_audio_path = temp_audio.name

                with open(temp_audio_path, "rb") as f:
                    audio_b64 = base64.b64encode(f.read()).decode("utf-8")

                os.remove(temp_audio_path)

                # Run Whisper transcription
                result = detect_language_and_transcribe_from_base64(audio_b64)
                lang, text = result["language"], result["text"]

                if text:
                    print(f"[{timestamp}] Speaker {speaker_id} ({lang}) → {text}")
                    recognized_results.append(
                        {
                            "timestamp": timestamp,
                            "speaker": f"Speaker {speaker_id}",
                            "lang": lang,
                            "text": text,
                        }
                    )
                    # Alternate speakers automatically
                    speaker_id = 2 if speaker_id == 1 else 1
                else:
                    print(f"[{timestamp}] Silence detected.")

            except Exception as e:
                print(f"[{timestamp}] Recognition error:", e)

    # Run recognition in a thread
    recorder = threading.Thread(target=recognize_loop, daemon=True)
    recorder.start()

    try:
        while True:
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\nUser requested stop. Returning recognized results...")
        stop_flag.set()
        recorder.join(timeout=2)
        print("Shutdown complete.")
        return recognized_results


if __name__ == "__main__":
    results = live_turn_taking_recognition()
    print("\n📝 Final recognized results:")
    for r in results:
        print(r)

    print("\n🌍 Translating recognized speech to Korean...")
    translated_results = translate_json_list(results, target_lang="ko")

    print("\n✅ Final Translated JSON:")
    for item in translated_results:
        print(item)
