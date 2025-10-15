import base64
import queue
import threading
import time
from datetime import datetime
import speech_recognition as sr
import tempfile
import os
import whisper
from speech_translation import translate_json_list  # translation module
import warnings

warnings.filterwarnings(
    "ignore", message="FP16 is not supported on CPU; using FP32 instead"
)
whisper_model = whisper.load_model("base")


def detect_language_and_transcribe_from_base64(audio_b64: str):
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


def live_listen_and_recognize(phrase_time_limit=None):
    """
    Real-time mic recognition with Whisper-based auto language detection.
    Returns:
    [
        {"timestamp": "20251010_153045", "lang": "en", "text": "hello my name is kevin"},
        {"timestamp": "20251010_153052", "lang": "ko", "text": "안녕하세요"}
    ]
    """
    r = sr.Recognizer()

    try:
        mic = sr.Microphone()
    except Exception as e:
        print("Microphone not found or cannot be opened:", e)
        raise

    with mic as source:
        print("Adjusting for ambient noise...")
        r.adjust_for_ambient_noise(source, duration=1.0)
        print(f"Done. Energy threshold: {r.energy_threshold}")

    stop_flag = threading.Event()
    audio_q = queue.Queue()
    recognized_results = []

    def record_loop():
        with mic as source:
            while not stop_flag.is_set():
                try:
                    audio = r.listen(
                        source, timeout=1, phrase_time_limit=phrase_time_limit
                    )
                    audio_q.put(audio)
                except sr.WaitTimeoutError:
                    continue
                except Exception as inner_e:
                    print("Recording error:", inner_e)
                    break

    recorder = threading.Thread(target=record_loop, daemon=True)
    recorder.start()
    print("🎤 Listening... Speak into your microphone. (Ctrl+C to stop)")

    try:
        while True:
            audio = audio_q.get()
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

            try:
                lang, text = detect_language_and_transcribe(audio)

                if text:
                    print(f"[{timestamp}] ({lang}) → {text}")
                    recognized_results.append(
                        {"timestamp": timestamp, "lang": lang, "text": text}
                    )
                else:
                    print(f"[{timestamp}] Silence detected.")

            except Exception as e:
                print(f"[{timestamp}] Recognition error:", e)

    except KeyboardInterrupt:
        print("\nUser requested stop. Returning recognized results...")
        stop_flag.set()
        recorder.join(timeout=2)
        print("Shutdown complete.")
        return recognized_results


if __name__ == "__main__":
    results = live_listen_and_recognize(phrase_time_limit=5)
    print("\n📝 Final recognized results:")
    print(results)

    print("\n🌍 Translating recognized speech to Korean...")
    translated_results = translate_json_list(results, target_lang="ko")

    print("\n✅ Final Translated JSON:")
    for item in translated_results:
        print(item)
