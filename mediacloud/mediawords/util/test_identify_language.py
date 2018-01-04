from mediawords.util.identify_language import *

__ENGLISH_TEXT = 'The quick brown fox jumps over the lazy dog.'
__RUSSIAN_TEXT = 'В чащах юга жил бы цитрус? Да, но фальшивый экземпляр!'


def test_language_code_for_text():
    assert language_code_for_text(text='') == ''
    # noinspection PyTypeChecker
    assert language_code_for_text(text=None) == ''

    assert language_code_for_text(text=__ENGLISH_TEXT) == 'en'
    assert language_code_for_text(text=__RUSSIAN_TEXT) == 'ru'


def test_language_code_for_text_uppercase():
    assert language_code_for_text(text=__ENGLISH_TEXT.upper()) == 'en'
    assert language_code_for_text(text=__RUSSIAN_TEXT.upper()) == 'ru'


def test_language_code_for_text_invalid_utf8():
    invalid_utf8_sequences = [
        "\xc3\x28",
        "\xa0\xa1",
        "\xe2\x28\xa1",
        "\xe2\x82\x28",
        "\xf0\x28\x8c\xbc",
        "\xf0\x90\x28\xbc",
        "\xf0\x28\x8c\x28",
        "\xf8\xa1\xa1\xa1\xa1",
        "\xfc\xa1\xa1\xa1\xa1\xa1",
    ]

    for invalid_sequence in invalid_utf8_sequences:
        # Make sure it doesn't raise
        assert language_code_for_text(text=invalid_sequence) == ''


def test_language_code_for_text_large_input():
    # 10 MB of 'a'
    very_long_string = 'a' * (1024 * 1024 * 10)
    assert len(very_long_string) > 1024 * 1024 * 9

    # Make sure it doesn't raise
    language_code_for_text(text=very_long_string)


def test_identification_would_be_reliable():
    assert identification_would_be_reliable(text='') is False
    # noinspection PyTypeChecker
    assert identification_would_be_reliable(text=None) is False

    assert identification_would_be_reliable(text=__ENGLISH_TEXT) is True
    assert identification_would_be_reliable(text=__RUSSIAN_TEXT) is True


def test_identification_would_be_reliable_digits():
    # Digits
    assert identification_would_be_reliable(text='0000000000000000000000') is False

    # More digits than letters
    assert identification_would_be_reliable(text='000000000000000aaaaaaa') is False


def test_language_is_supported():
    assert language_is_supported(code='') is False
    # noinspection PyTypeChecker
    assert language_is_supported(code=None) is False

    assert language_is_supported(code='en') is True
    assert language_is_supported(code='ru') is True

    assert language_is_supported(code='xx') is False


def test_language_name_for_code():
    assert language_name_for_code(code='') == ''
    # noinspection PyTypeChecker
    assert language_name_for_code(code=None) == ''

    assert language_name_for_code(code='en') == 'English'
    assert language_name_for_code(code='ru') == 'Russian'

    # Underscore replacement
    assert language_name_for_code(code='ht') == 'Haitian Creole'

    assert language_name_for_code(code='xx') == ''
