import cv2
import time
import threading
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

        emotion = detect_emotion(frame)

        if collecting:
            emotion_buffer.append(emotion)

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
        return "Unknown"

    counter = Counter(emotion_buffer)
    dominant = counter.most_common(1)[0][0]
    print(f"🎯 Final Dominant Emotion: {dominant}")
    return dominant


# API connection
def start_collection():
    thread = threading.Thread(target=lambda: print(collect_emotions(5)))
    thread.start()


if __name__ == "__main__":
    threading.Thread(target=video_stream, daemon=True).start()

    input("Press Enter to start collecting emotion for 5 seconds...")
    start_collection()
