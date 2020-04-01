import pytest

from mediawords.util.text import McRandomStringException, random_string, escape_for_repr


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


def test_escape_for_repr():
    assert escape_for_repr(None) == "None"
    assert escape_for_repr('a') == "'a'"
    assert escape_for_repr(1) == "1"
    assert escape_for_repr(1.23) == "1.23"
    assert escape_for_repr(b'abcdef') == "b'abcdef'"
