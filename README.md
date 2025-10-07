# EmoAI-Translator
This project combines TTS(text-to-speech) technology along with Computer vision to translate the words you say using the emotions being displayed. This is still a work in progress and is far from done, but the core elements are implemented and I am open to suggestions.

## Features
- Real-time emotion detection using DeepFace.
- Text-to-speech with emotion adjustments (rate, pitch).
- Text translation with language support.

## Installation
1. Clone the repository:
```bash
git clone https://github.com/EmoAI-Translator/EmoAI-Translator.git
```

2. Install the required dependencies:
```bash
 cd backend
 pip install -r requirements.txt
```

## Dependencies
This project requires the following model for facial landmark detection:
- 68 Facial Landmarks Model: Used for facial feature detection in real-time. You can download it from [This Link](https://github.com/italojs/facial-landmarks-recognition/blob/master/shape_predictor_68_face_landmarks.dat):


### Instructions for Setting Up the Model:
Download the shape_predictor_68_face_landmarks.dat file from the link above.
Place it in the "models/" folder in the root directory of your project (or wherever your project is located).
Update the code to point to the correct path for the file.

## Usage
- Run the Python script:
   python emotion_translation.py

- Hold the "Record" button to start voice input and see the emotion-based speech output.

## Credits and Acknowledgements
This project uses several third-party libraries and APIs that provide essential functionality:

- DeepFace: Used for emotion detection, providing state-of-the-art facial recognition and emotion analysis. DeepFace GitHub Repository
- Google Translate API: Used for translation functionality. Google Translate API Documentation
- pyttsx3: Text-to-Speech conversion library. pyttsx3 GitHub Repository
- Dlib: The shape_predictor_68_face_landmarks.dat model for facial landmark detection. Dlib GitHub Repository

## Contributing
Contributions are welcome! Feel free to improve the repository and submit a pull request.

## Documentation

All contribution guidelines and workflows are documented in the [project Wiki](https://github.com/EmoAI-Translator/EmoAI-Translator/wiki/EmoAI-Git-Collaboration-Guide). Make sure to check it before starting your work.

## Contact
For questions, please contact axeltt24@gmail.com
