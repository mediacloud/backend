from typing import Dict

import cld2

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

# Min. text length for reliable language identification
__RELIABLE_IDENTIFICATION_MIN_TEXT_LENGTH = 10

# Don't process strings longer than the following length
__MAX_TEXT_LENGTH = 1024 * 1024

log = create_logger(__name__)


def __create_supported_language_mapping() -> Dict[str, str]:
    """Create and return language code -> language name dict."""
    supported_languages_tuple = cld2.LANGUAGES
    codes_to_names = dict()
    for language_name, language_code in supported_languages_tuple:

        # Tuple members are in 'bytes'
        language_name = language_name.decode('utf-8').lower()
        language_code = language_code.decode('utf-8').lower()

        # Don't include "X_Malayalam" and "xx-Mlym"
        if language_name.startswith('X_') or language_code.startswith('xx-'):
            continue

        # Don't include extended languages such as "zh-hant"
        if len(language_code) > 3:
            continue

        codes_to_names[language_code] = language_name

    return codes_to_names


__LANGUAGE_CODES_TO_NAMES = __create_supported_language_mapping()


def __recode_utf8_string(utf8_string: str) -> str:
    """Encode and then decode UTF-8 string by removing invalid characters in the process."""
    return utf8_string.encode('utf-8', errors='replace').decode('utf-8', errors='replace')


def language_code_for_text(text: str):
    """Returns an ISO 690 language code for the plain text passed as a parameter.

    :param text: Text that should be identified
    :return: ISO 690 language code (e.g. 'en') on successful identification, empty string ('') on failure
    """
    text = decode_object_from_bytes_if_needed(text)

    if not text:
        return ''

    if len(text) > __MAX_TEXT_LENGTH:
        log.warning("Text is longer than %d, trimming..." % __MAX_TEXT_LENGTH)
        text = text[:__MAX_TEXT_LENGTH]

    # We need to verify that the file can cleany encode and decode because CLD can segfault on bad UTF-8
    text = __recode_utf8_string(text)

    try:
        is_reliable, text_bytes_found, details = cld2.detect(utf8Bytes=text, useFullLangTables=True)
    except Exception as ex:
        log.error("Error while detecting language: %s" % str(ex))
        return ''

    if not details:
        return ''

    best_match = details[0]
    language_name = best_match.language_name.lower()
    language_code = best_match.language_code.lower()

    if language_name in {'unknown', 'tg_unknown_language'} or language_code == 'un':
        return ''

    if not language_is_supported(language_code):
        return ''

    return language_code


def identification_would_be_reliable(text: str) -> bool:
    """Returns True if the language identification for the text passed as a parameter is likely to be reliable.

    :param text: Text that should be identified
    :return: True if language identification is likely to be reliable; False otherwise
    """
    text = decode_object_from_bytes_if_needed(text)

    if not text:
        return False

    # Too short?
    if len(text) < __RELIABLE_IDENTIFICATION_MIN_TEXT_LENGTH:
        return False

    if len(text) > __MAX_TEXT_LENGTH:
        log.warning("Text is longer than %s, trimming..." % __MAX_TEXT_LENGTH)
        text = text[:__MAX_TEXT_LENGTH]

    text = __recode_utf8_string(text)

    # Not enough letters as opposed to non-letters?
    word_character_count = 0
    digit_count = 0
    underscore_count = 0
    for character in text:
        if character.isalpha():
            word_character_count += 1
        if character.isdigit():
            digit_count += 1
        if character == '_':
            underscore_count += 1

    letter_count = word_character_count - digit_count - underscore_count
    if letter_count < __RELIABLE_IDENTIFICATION_MIN_TEXT_LENGTH:
        return False

    return True


def language_is_supported(code: str) -> bool:
    """Returns True if the language code if supported by the identifier.

    :param code: ISO 639-1 language code
    :return: True if the language can be identified, False if it can not
    """
    code = decode_object_from_bytes_if_needed(code)

    if not code:
        return False

    return code in __LANGUAGE_CODES_TO_NAMES


# MC_REWRITE_TO_PYTHON make it return Union[str, None] after Perl -> Python rewrite
def language_name_for_code(code: str) -> str:
    """Return the human readable language name for a given language code.

    :param code: ISO 639-1 language code
    :return: Language name, e.g. "Lithuanian", or an empty string ('') if language is not supported
    """
    code = decode_object_from_bytes_if_needed(code)

    if not code:
        return ''

    if code not in __LANGUAGE_CODES_TO_NAMES:
        return ''

    language_name = __LANGUAGE_CODES_TO_NAMES[code]

    language_name = language_name.replace('_', ' ')

    return language_name.title()
