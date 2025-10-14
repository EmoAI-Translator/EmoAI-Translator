from googletrans import Translator
from datetime import datetime

# Initialize translator
translator = Translator()

def translate_json_list(json_list, target_lang="ko"):
    """
    Translates a list of recognized speech JSON objects into another language.

    Args:
        json_list (list): [{"timestamp": "20251010_153045", "text": "hello my name is kevin"}, ...]
        target_lang (str): Target translation language (e.g. 'ko', 'es', 'fr')

    Returns:
        list: [{"timestamp": "...", "original_text": "...", "translated_text": "..."}]
    """
    translated_results = []

    for item in json_list:
        original_text = item
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        try:
            # Translate using Google Translate API
            translated = translator.translate(original_text, dest=target_lang)

            translated_results.append({
                "timestamp": timestamp,
                "original_text": original_text,
                "translated_text": translated.text
            })

            print(f"[{timestamp}] {original_text} → {translated.text}")

        except Exception as e:
            print(f"⚠️ Translation error for '{original_text}': {e}")
            translated_results.append({
                "timestamp": timestamp,
                "original_text": original_text,
                "translated_text": None
            })

    return translated_results


if __name__ == "__main__":
    # Example test
    sample_input = [
        {"timestamp": "20251010_153045", "text": "hello my name is kevin"},
        {"timestamp": "20251010_153052", "text": "nice to meet you"}
    ]

    result = translate_json_list(sample_input, target_lang="ko")
    print("\nFinal translated JSON:")
    for r in result:
        print(r)