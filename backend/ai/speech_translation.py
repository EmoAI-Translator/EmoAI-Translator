from googletrans import Translator

import boto3
from datetime import datetime


translate_client = boto3.client(
    "translate",
    region_name="us-east-1"  # Align with EC2 region
)

def translate_json_list(json_list, target_lang):
    translated_results = []

    for item in json_list:
        original_text = item.get("text", "")
        timestamp = item.get("timestamp") or datetime.utcnow().isoformat()

        try:
            response = translate_client.translate_text(
                Text=original_text,
                SourceLanguageCode="auto",
                TargetLanguageCode=target_lang,
            )

            translated_text = response["TranslatedText"]

            translated_results.append(
                {
                    "timestamp": timestamp,
                    "original_text": original_text,
                    "translated_text": translated_text,
                }
            )

        except Exception as e:
            print(f"⚠️ AWS Translate error: {e}")
            translated_results.append(
                {
                    "timestamp": timestamp,
                    "original_text": original_text,
                    "translated_text": None,
                }
            )

    return translated_results

if __name__ == "__main__":
    # Example test
    sample_input = [
        {"timestamp": "20251010_153045", "text": "hello my name is kevin"},
        {"timestamp": "20251010_153052", "text": "nice to meet you"},
    ]

    result = translate_json_list(sample_input, target_lang="ko")
    print("\nFinal translated JSON:")
    for r in result:
        print(r)











# Initialize translator
# translator = Translator()


# async def translate_json_list(json_list, target_lang):
#     """
#     Translates a list of recognized speech JSON objects into another language.

#     Args:
#         json_list (list): [{"timestamp": "20251010_153045", "text": "hello my name is kevin"}, ...]
#         target_lang (str): Target translation language (e.g. 'ko', 'es', 'fr')

#     Returns:
#         list: [{"timestamp": "...", "original_text": "...", "translated_text": "..."}]
#     """
#     translated_results = []

#     for item in json_list:
#         original_text = item.get("text", "")
#         timestamp = item.get("timestamp") or datetime.now().strftime("%Y%m%d_%H%M%S")

#         try:
#             # Translate using Google Translate API
#             translated = await translator.translate(original_text, dest=target_lang)

#             translated_results.append(
#                 {
#                     "timestamp": timestamp,
#                     "original_text": original_text,
#                     "translated_text": translated.text,
#                 }
#             )

#             print(f"[{timestamp}] {original_text} → {translated.text}")

#         except Exception as e:
#             print(f"⚠️ Translation error for '{original_text}': {e}")
#             translated_results.append(
#                 {
#                     "timestamp": timestamp,
#                     "original_text": original_text,
#                     "translated_text": None,
#                 }
#             )

#     return translated_results


# if __name__ == "__main__":
#     # Example test
#     sample_input = [
#         {"timestamp": "20251010_153045", "text": "hello my name is kevin"},
#         {"timestamp": "20251010_153052", "text": "nice to meet you"},
#     ]

#     result = translate_json_list(sample_input, target_lang="ko")
#     print("\nFinal translated JSON:")
#     for r in result:
#         print(r)
