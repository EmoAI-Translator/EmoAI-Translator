import base64
import queue
import threading
import time
from datetime import datetime
import speech_recognition as sr
import tempfile
import os
import whisper
from speech_translation import translate_json_list
import warnings
import torch
import librosa
from transformers import AutoFeatureExtractor, AutoModelForAudioClassification

warnings.filterwarnings(
    "ignore", message="FP16 is not supported on CPU; using FP32 instead"
)

# -------------------------------
# Load Models Once
# -------------------------------
whisper_model = whisper.load_model("base")
emotion_model_name = "superb/wav2vec2-base-superb-er"
emotion_extractor = AutoFeatureExtractor.from_pretrained(emotion_model_name)
emotion_model = AutoModelForAudioClassification.from_pretrained(emotion_model_name)


# -------------------------------
# Emotion Detection Function
# -------------------------------
def detect_emotion_from_audio(wav_path: str):
    """
    Returns: {"emotion": str, "scores": dict}
    """
    speech, sr = librosa.load(wav_path, sr=16000)
    inputs = emotion_extractor(speech, sampling_rate=16000, return_tensors="pt")

    with torch.no_grad():
        logits = emotion_model(**inputs).logits
        probs = torch.nn.functional.softmax(logits, dim=-1)[0]
        pred_id = torch.argmax(probs).item()

    label = emotion_model.config.id2label[pred_id]
    scores = {
        emotion_model.config.id2label[i]: round(float(probs[i]), 4)
        for i in range(len(probs))
    }
    return {"emotion": label, "scores": scores}


# -------------------------------
# Whisper Transcription + Language
# -------------------------------
def detect_language_and_transcribe_from_base64(audio_b64: str):
    """Decode base64 WAV, transcribe, detect language."""
    audio_bytes = base64.b64decode(audio_b64)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_wav:
        temp_wav.write(audio_bytes)
        temp_path = temp_wav.name

    try:
        result = whisper_model.transcribe(temp_path)
        emotion_result = detect_emotion_from_audio(temp_path)
    finally:
        os.remove(temp_path)

    language = result.get("language", "unknown")
    text = result.get("text", "").strip()
    emotion = emotion_result["emotion"]
    scores = emotion_result["scores"]

    return {"language": language, "text": text, "emotion": emotion, "scores": scores}


# -------------------------------
# Real-time Speech Recognition Loop
# -------------------------------
def live_turn_taking_recognition():
    """
    Real-time microphone recognition with Whisper-based language detection + Emotion detection.
    Detects turns based on silence and alternates speakers automatically.
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

                # Run Whisper + Emotion
                result = detect_language_and_transcribe_from_base64(audio_b64)
                lang, text, emotion, scores = (
                    result["language"],
                    result["text"],
                    result["emotion"],
                    result["scores"],
                )

                if text:
                    print(f"[{timestamp}] Speaker {speaker_id} ({lang}) → {text}")
                    print(f"   🎭 Emotion: {emotion} {scores}")

                    recognized_results.append(
                        {
                            "timestamp": timestamp,
                            "speaker": f"Speaker {speaker_id}",
                            "lang": lang,
                            "text": text,
                            "emotion": emotion,
                            "emotion_scores": scores,
                        }
                    )

                    speaker_id = 2 if speaker_id == 1 else 1
                else:
                    print(f"[{timestamp}] Silence detected.")

            except Exception as e:
                print(f"[{timestamp}] Recognition error:", e)

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


# -------------------------------
# Main Entry
# -------------------------------
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
