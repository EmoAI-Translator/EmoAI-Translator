import cv2
import time
import threading
import json
from collections import Counter
from deepface import DeepFace

current_emotion = "Neutral"
emotion_buffer = []
collecting = False


# Emotion Detection Function
def detect_emotion(frame):
    global current_emotion
    try:
        result = DeepFace.analyze(frame, actions=["emotion"], enforce_detection=False)
        emotions = result[0]["emotion"]
        dominant = result[0]["dominant_emotion"]

        if emotions.get("happy", 0) > 30:
            dominant = "happy"

        current_emotion = dominant.capitalize()
        return current_emotion
    except Exception:
        current_emotion = "Unknown"
        return current_emotion


# Video Stream and Display
def video_stream():
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Webcam access failed.")
        return

    while True:
        success, frame = cap.read()
        if not success:
            break

        detect_emotion(frame)

        if collecting:
            emotion_buffer.append(current_emotion)

        if cv2.waitKey(1) & 0xFF == 27:
            break

    cap.release()
    cv2.destroyAllWindows()


# Emotion Collection Logic
def collect_emotions(duration=5):
    global emotion_buffer, collecting
    emotion_buffer = []
    collecting = True
    print(f"⏳ Collecting emotions for {duration} seconds...")

    time.sleep(duration)
    collecting = False
    print("Collection finished.")
    return get_average_emotion()


# Average Emotion Calculation
def get_average_emotion():
    if not emotion_buffer:
        return {"status": "failed", "dominant_emotion": "Unknown"}

    counter = Counter(emotion_buffer)
    dominant, count = counter.most_common(1)[0]
    total = sum(counter.values())

    data = {
        "status": "success",
        "dominant_emotion": dominant,
        "emotion_distribution": dict(counter),
        "sample_count": total,
    }

    print(f"🎯 Final Dominant Emotion: {dominant}")
    return data


# Public API function (returns JSON)
def start_collection(duration=5):
    def run_collection():
        result = collect_emotions(duration)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return result

    thread = threading.Thread(target=run_collection)
    thread.start()


# Background thread to keep webcam running
def start_video_stream():
    threading.Thread(target=video_stream, daemon=True).start()
