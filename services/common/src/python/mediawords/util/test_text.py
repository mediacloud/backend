import pytest

from mediawords.util.text import McRandomStringException, random_string


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
