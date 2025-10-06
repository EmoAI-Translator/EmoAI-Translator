import cv2
import pyttsx3
import speech_recognition as sr
import asyncio
import threading
from tkinter import Tk, StringVar, Entry, Button, Label, OptionMenu
from threading import Thread
from deepface import DeepFace
from googletrans import Translator

# Initialize TTS engine
engine = pyttsx3.init()

# Initialize global variables
current_emotion = "Neutral"  # To store the current detected emotion
frozen_emotion = "Neutral"  # To store the emotion when recording starts
recording = False

# Initialize translator
translator = Translator()

# Function to detect emotion using DeepFace
def detect_emotion(frame):
    global current_emotion
    # Analyze the frame for emotions using DeepFace
    result = DeepFace.analyze(frame, actions=['emotion'], enforce_detection=False)

    # Get the dominant emotion
    current_emotion = result[0]['dominant_emotion']
    
    # Remove console print statement for emotion, only update the GUI
    return current_emotion

# Function to capture video and process emotions
def video_stream():
    global current_emotion
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Unable to access the webcam.")
        return

    while True:
        success, frame = cap.read()
        if not success:
            break

        # Detect emotion
        emotion = detect_emotion(frame)

        # Update the current emotion
        current_emotion = emotion

        # Draw bounding box and emotion label
        cv2.putText(frame, f"Emotion: {current_emotion}", (50, 50),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)

        cv2.imshow("Emotion Detection", frame)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()

# Function to handle button click for manual input
def on_button_click():
    text = input_text.get()
    if frozen_emotion:
        speak_text(text, frozen_emotion)
    else:
        speak_text(text, "Neutral")

# Function for TTS with emotion-specific tone
def speak_text(text, emotion):
    if emotion == "Happy":
        engine.setProperty("rate", 180)
        engine.setProperty("volume", 2.5)
    elif emotion == "Surprised":
        engine.setProperty("rate", 180)
        engine.setProperty("volume", 0.8)
    elif emotion == "Sad":
        engine.setProperty("rate", 80)
        engine.setProperty("volume", 0.5)
    else:
        engine.setProperty("rate", 100)
        engine.setProperty("volume", 1.0)
    engine.say(text)
    engine.runAndWait()

# Function to translate text asynchronously
async def translate_text():
    text = input_text.get()
    print(f"Text to translate: {text}")  # Debugging: Check what is being passed for translation
    if not text:
        return
    # Await the translation result (assuming you use an asynchronous googletrans version)
    translated = await translator.translate(text, dest=selected_language.get())
    translated_text.set(f"Translated: {translated.text}")
    speak_text(translated.text, current_emotion)

    # Function to run translate_text in an event loop
def run_translation_in_thread():
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(translate_text())

# Function to handle voice input and convert it to text
def start_recording():
    global recording
    recognizer = sr.Recognizer()
    mic = sr.Microphone()

    with mic as source:
        recognizer.adjust_for_ambient_noise(source)
        print("Recording... Speak now.")
        while recording:  # Continuously listen while holding the button
            try:
                audio = recognizer.listen(source)
                print("Recognizing...")
                text = recognizer.recognize_google(audio)
                print("You said: " + text)

                # Update the input_text StringVar with the recognized text
                input_text.set(text)

                # Start a new thread for translation to avoid blocking
                translation_thread = threading.Thread(target=run_translation_in_thread)
                translation_thread.start()

            except sr.UnknownValueError:
                print("Sorry, I could not understand the audio.")
            except sr.RequestError:
                print("Sorry, there was an error with the request.")

# Function to start the video stream in a separate thread
def start_video_thread():
    video_thread = Thread(target=video_stream, daemon=True)
    video_thread.start()

# Function to start and stop recording based on button events
def on_button_press(event):
    global recording
    recording = True
    start_recording_thread = Thread(target=start_recording)
    start_recording_thread.start()

def on_button_release(event):
    global recording
    recording = False

# Initialize Tkinter GUI
root = Tk()
root.title("Emotion Voice Translation")

# Input text field for the user
input_text = StringVar()
Entry(root, textvariable=input_text, width=50).pack(pady=10)

# Translated text display
translated_text = StringVar(value="Translated: ")
Label(root, textvariable=translated_text, font=("Arial", 12)).pack(pady=5)

# Language selection dropdown
languages = {"Spanish": "spanish", "French": "french", "German": "deutch", "Chinese": "chinese"}
selected_language = StringVar(value="spanish")  # Default to Spanish
OptionMenu(root, selected_language, *languages.values()).pack(pady=5)

# Button to start voice input recording
record_button = Button(root, text="Hold to Record")
record_button.pack(pady=10)

# Bind button press and release events
record_button.bind("<ButtonPress-1>", on_button_press)
record_button.bind("<ButtonRelease-1>", on_button_release)

# Start video stream thread
start_video_thread()

# Main Tkinter loop
root.mainloop()
