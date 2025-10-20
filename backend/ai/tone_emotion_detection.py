import sounddevice as sd
import numpy as np
from transformers import AutoFeatureExtractor, AutoModelForAudioClassification
import torch

model_name = "superb/wav2vec2-base-superb-er"
extractor = AutoFeatureExtractor.from_pretrained(model_name)
model = AutoModelForAudioClassification.from_pretrained(model_name)


def predict_emotion(audio_data, sr=16000):
    inputs = extractor(audio_data, sampling_rate=sr, return_tensors="pt")
    with torch.no_grad():
        logits = model(**inputs).logits
    pred_id = torch.argmax(logits, dim=-1).item()
    return model.config.id2label[pred_id]


duration = 3
print("🎙️ 말하세요...")

audio = sd.rec(int(duration * 16000), samplerate=16000, channels=1, dtype="float32")
sd.wait()

emotion = predict_emotion(np.squeeze(audio))
print("예측된 감정:", emotion)
