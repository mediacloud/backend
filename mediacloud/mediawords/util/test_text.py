import pytest

from mediawords.util.text import McRandomStringException, random_string, replace_control_nonprintable_characters


def test_random_string():
    with pytest.raises(McRandomStringException):
        random_string(0)
    with pytest.raises(McRandomStringException):
        random_string(-1)

    length = 16
    string_1 = random_string(length=length)
    string_2 = random_string(length=length)

    assert string_1 != string_2
    assert len(string_1) == length
    assert len(string_2) == length
    assert string_1.isalnum()
    assert string_2.isalnum()


def test_replace_control_nonprintable_characters():
    # "Ḃ" is 0x1E02, and if the function happened to input as bytes (i.e. without UTF-8 awareness),
    # it might choose to strip 0x02 part, so we need to test for that
    unicode_character = "Ḃ"
    input_string = (b"\x00a\nb\r\nc\td\x7fe" + unicode_character.encode('utf-8') + b"f").decode('utf-8')
    replacement = 'xyz'
    expected_string = f"{replacement}a\nb\r\nc\td{replacement}e{unicode_character}f"
    actual_string = replace_control_nonprintable_characters(string=input_string, replacement=replacement)
    assert expected_string == actual_string
