from connection import db

sample_user = {
    "email": "woo@emoai.com",
    "nickname": "Woochul",
    "createdAt": "2025-10-07"
}

sample_emotion = {
    "user_id": "12345",
    "emotion": "happy",
    "confidence": 0.93,
    "timestamp": "2025-10-07T21:30:00Z"
}

sample_translation = {
    "user_id": "12345",
    "original_text": "Hello, how are you?",
    "translated_text": "안녕하세요, 어떻게 지내세요?",
    "source_language": "en",
    "target_language": "ko",
    "timestamp": "2025-10-07T21:35:00Z"
}

# db.translations.insert_one(sample_emotion)
# print("Translations collection test data inserted")

# result = db.users.insert_one(sample_user)
# print("Inserted user with ID:", result.inserted_id)