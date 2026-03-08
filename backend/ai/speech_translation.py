from googletrans import Translator
from datetime import datetime
import logging

# Initialize translator
translator = Translator()
logger = logging.getLogger(__name__)

def translate_json_list(json_list, target_lang):
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
        original_text = item.get("text", "")
        timestamp = item.get("timestamp") or datetime.now().strftime("%Y%m%d_%H%M%S")

        try:
            # Translate using Google Translate API
            translated = translator.translate(original_text, dest=target_lang)

            translated_results.append(
                {
                    "timestamp": timestamp,
                    "original_text": original_text,
                    "translated_text": translated.text,
                }
            )

            logger.info("[%s] %s -> %s", timestamp, original_text, translated.text)

        except Exception:
            logger.exception("Translation error for %r", original_text)
            translated_results.append(
                {
                    "timestamp": timestamp,
                    "original_text": original_text,
                    "translated_text": None,
                }
            )

    return translated_results


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    # Example test
    sample_input = [
        {"timestamp": "20251010_153045", "text": "hello my name is kevin"},
        {"timestamp": "20251010_153052", "text": "nice to meet you"}
    ]

    result = translate_json_list(sample_input, target_lang="ko")
    logger.info("Final translated JSON:")
    for r in result:
        logger.info("%s", r)
