import base64
import io
import logging
import queue
import threading
import time
import wave
from datetime import datetime
import speech_recognition as sr
import tempfile
import os
import whisper
from ai.speech_translation import translate_json_list
import warnings
import numpy as np
import torch
from time import perf_counter
from transformers import AutoFeatureExtractor, AutoModelForAudioClassification

warnings.filterwarnings(
    "ignore", message="FP16 is not supported on CPU; using FP32 instead"
)
logger = logging.getLogger(__name__)

# -------------------------------
# Load Models Once
# -------------------------------
WHISPER_DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
EMOTION_DEVICE = "cpu"
WHISPER_FP16 = WHISPER_DEVICE == "cuda"

whisper_model = whisper.load_model("base", device=WHISPER_DEVICE)
emotion_model_name = "superb/wav2vec2-base-superb-er"
emotion_extractor = AutoFeatureExtractor.from_pretrained(emotion_model_name)
emotion_model = AutoModelForAudioClassification.from_pretrained(
    emotion_model_name
).to(EMOTION_DEVICE)
emotion_model.eval()

logger.info(
    "AI runtime initialized: cuda_available=%s selected_device=%s whisper_device=%s emotion_device=%s",
    torch.cuda.is_available(),
    WHISPER_DEVICE,
    getattr(whisper_model, "device", WHISPER_DEVICE),
    next(emotion_model.parameters()).device,
)
if WHISPER_DEVICE != "cuda":
    logger.warning(
        "CUDA is unavailable or PyTorch is CPU-only. Falling back to CPU inference for Whisper."
    )


# -------------------------------
# Emotion Detection Function
# -------------------------------
def _resample_audio(audio: np.ndarray, src_sr: int, dst_sr: int) -> np.ndarray:
    if src_sr == dst_sr or audio.size == 0:
        return audio

    duration = audio.shape[0] / float(src_sr)
    target_length = max(1, int(round(duration * dst_sr)))
    src_positions = np.arange(audio.shape[0], dtype=np.float32)
    dst_positions = np.linspace(0, audio.shape[0] - 1, num=target_length, dtype=np.float32)
    return np.interp(dst_positions, src_positions, audio).astype(np.float32)


def _load_wav_bytes(wav_bytes: bytes, target_sr: int = 16000) -> np.ndarray:
    with wave.open(io.BytesIO(wav_bytes), "rb") as wav_file:
        num_channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        sample_rate = wav_file.getframerate()
        frame_count = wav_file.getnframes()
        frames = wav_file.readframes(frame_count)

    if sample_width == 1:
        audio = np.frombuffer(frames, dtype=np.uint8).astype(np.float32)
        audio = (audio - 128.0) / 128.0
    elif sample_width == 2:
        audio = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
    elif sample_width == 4:
        audio = np.frombuffer(frames, dtype=np.int32).astype(np.float32) / 2147483648.0
    else:
        raise ValueError(f"Unsupported WAV sample width: {sample_width}")

    if num_channels > 1:
        audio = audio.reshape(-1, num_channels).mean(axis=1)

    return _resample_audio(audio, sample_rate, target_sr)


def detect_emotion_from_audio(wav_bytes: bytes):
    """
    Returns: {"emotion": str, "scores": dict}
    """
    timings = {}

    t1 = perf_counter()
    speech = _load_wav_bytes(wav_bytes, target_sr=16000)
    t2 = perf_counter()
    timings["emotion_load"] = (t2 - t1) * 1000

    t3 = perf_counter()
    inputs = emotion_extractor(speech, sampling_rate=16000, return_tensors="pt")
    inputs = {key: value.to(EMOTION_DEVICE) for key, value in inputs.items()}
    t4 = perf_counter()
    timings["emotion_extract"] = (t4 - t3) * 1000

    t5 = perf_counter()
    with torch.no_grad():
        logits = emotion_model(**inputs).logits
        probs = torch.nn.functional.softmax(logits, dim=-1)[0].detach().cpu()
        pred_id = torch.argmax(probs).item()
    t6 = perf_counter()
    timings["emotion_forward"] = (t6 - t5) * 1000

    t7 = perf_counter()
    label = emotion_model.config.id2label[pred_id]
    scores = {
        emotion_model.config.id2label[i]: round(float(probs[i]), 4)
        for i in range(len(probs))
    }
    t8 = perf_counter()
    timings["emotion_postprocess"] = (t8 - t7) * 1000
    timings["emotion_total"] = sum(timings.values())

    return {"emotion": label, "scores": scores, "timings": timings}


# -------------------------------
# Whisper Transcription + Language
# -------------------------------
def detect_language_and_transcribe_from_base64(audio_b64: str):
    """Decode base64 WAV, transcribe, detect language."""
    timings = {}
    t0 = perf_counter()

    t1 = perf_counter()
    audio_bytes = base64.b64decode(audio_b64)
    t2 = perf_counter()
    timings["decode_b64"] = (t2 - t1) * 1000

    t3 = perf_counter()
    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_wav:
        temp_wav.write(audio_bytes)
        temp_path = temp_wav.name
    t4 = perf_counter()
    timings["write_temp"] = (t4 - t3) * 1000

    try:
        t5 = perf_counter()
        result = whisper_model.transcribe(temp_path, fp16=WHISPER_FP16)
        t6 = perf_counter()
        timings["whisper"] = (t6 - t5) * 1000

        t7 = perf_counter()
        emotion_result = detect_emotion_from_audio(audio_bytes)
        t8 = perf_counter()
        timings["emotion"] = (t8 - t7) * 1000
        timings.update(emotion_result.get("timings", {}))
    finally:
        t9 = perf_counter()
        os.remove(temp_path)
        t10 = perf_counter()
        timings["cleanup"] = (t10 - t9) * 1000

    timings["detect_total"] = (perf_counter() - t0) * 1000

    language = result.get("language", "unknown")
    text = result.get("text", "").strip()
    emotion = emotion_result["emotion"]
    scores = emotion_result["scores"]

    return {
        "language": language,
        "text": text,
        "emotion": emotion,
        "scores": scores,
        "timings": timings,
    }


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
    except Exception:
        logger.exception("Microphone not found or cannot be opened")
        raise

    with mic as source:
        logger.info("Adjusting for ambient noise...")
        r.adjust_for_ambient_noise(source, duration=1.0)
        logger.info(
            "Ambient noise calibration complete. Energy threshold: %s",
            r.energy_threshold,
        )

    stop_flag = threading.Event()
    recognized_results = []

    def recognize_loop():
        speaker_id = 1
        logger.info("Listening. Speak into your microphone. Press Ctrl+C to stop.")

        while not stop_flag.is_set():
            with mic as source:
                try:
                    logger.info(
                        "Speaker %s speaking. Recording will stop on silence.",
                        speaker_id,
                    )
                    audio = r.listen(source, timeout=None)
                except Exception:
                    logger.exception("Recording error")
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
                    logger.info(
                        "[%s] Speaker %s (%s) -> %s",
                        timestamp,
                        speaker_id,
                        lang,
                        text,
                    )
                    logger.info("[%s] Emotion: %s %s", timestamp, emotion, scores)

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
                    logger.info("[%s] Silence detected.", timestamp)

            except Exception:
                logger.exception("[%s] Recognition error", timestamp)

    recorder = threading.Thread(target=recognize_loop, daemon=True)
    recorder.start()

    try:
        while True:
            time.sleep(0.5)
    except KeyboardInterrupt:
        logger.info("User requested stop. Returning recognized results...")
        stop_flag.set()
        recorder.join(timeout=2)
        logger.info("Shutdown complete.")
        return recognized_results


# -------------------------------
# Main Entry
# -------------------------------
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )
    results = live_turn_taking_recognition()
    logger.info("Final recognized results:")
    for r in results:
        logger.info("%s", r)

    logger.info("Translating recognized speech to Korean...")
    translated_results = translate_json_list(results, target_lang="ko")

    logger.info("Final translated JSON:")
    for item in translated_results:
        logger.info("%s", item)
