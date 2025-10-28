import os
import base64
from pathlib import Path
from TTS.api import TTS

# Initialize TTS models (they will be downloaded on first run)
# Using specific model names that are known to exist
tts_kr = TTS(model_name="tts_models/kr/glow-tts/korean_university-1.0", progress_bar=False)
tts_en = TTS(model_name="tts_models/en/ljspeech/glow-tts", progress_bar=False)

def text_to_speech(text, lang="ko"):
    """
    Convert text to speech using Coqui TTS and return base64 encoded audio
    
    Args:
        text (str): Text to convert to speech
        lang (str): Language code ('ko' or 'en')
    
    Returns:
        dict: Contains base64 encoded audio and metadata
    """
    try:
        # Select appropriate TTS model
        tts = tts_kr if lang.lower().startswith("ko") else tts_en
        
        # Generate unique filename
        output_path = f"tts_output_{hash(text)}.wav"
        
        # Generate speech
        tts.tts_to_file(text=text, file_path=output_path)
        
        # Read the generated audio file and encode to base64
        with open(output_path, "rb") as audio_file:
            audio_base64 = base64.b64encode(audio_file.read()).decode('utf-8')
            
        # Clean up the temporary file
        os.remove(output_path)
        
        return {
            "status": "success",
            "audio": audio_base64,
            "format": "wav",
            "lang": lang,
            "text": text
        }
        
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "lang": lang,
            "text": text
        }