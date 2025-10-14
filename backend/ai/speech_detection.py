import queue
import threading
import time
from datetime import datetime
import speech_recognition as sr
from speech_translation import translate_json_list  # translation module


def recognize_with_google(recognizer, audio_data, language="en-US"):
    text = recognizer.recognize_google(audio_data, language=language)
    return text


def live_listen_and_recognize(language="en-US", phrase_time_limit=None):
    """
    json return
    [
        {"timestamp": "20251010_153045", "text": "hello my name is kevin"},
        {"timestamp": "20251010_153052", "text": "nice to meet you"}
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
    print("Listening... Speak into your microphone. (Ctrl+C to stop)")

    try:
        while True:
            audio = audio_q.get()
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

            try:
                text = recognize_with_google(r, audio, language=language)
                print(f"[{timestamp}] Recognition result: {text}")

                recognized_results.append({"timestamp": timestamp, "text": text})

            except sr.UnknownValueError:
                print(f"[{timestamp}] Could not understand audio.")
            except sr.RequestError as e:
                print(f"[{timestamp}] Request error: {e}")
            except Exception as e:
                print(f"[{timestamp}] Unknown error:", e)

    except KeyboardInterrupt:
        print("\nUser requested stop. Returning recognized results...")
        stop_flag.set()
        recorder.join(timeout=2)
        print("Shutdown complete.")
        return recognized_results


if __name__ == "__main__":
    results = live_listen_and_recognize(language="en-US", phrase_time_limit=5)
    print("\nFinal recognized results (JSON-like):")
    print(results)

    print("\n🌍 Translating recognized speech...")
    translated_results = translate_json_list(results, target_lang="ko")

    print("\n✅ Final Translated JSON:")
    for item in translated_results:
        print(item)
