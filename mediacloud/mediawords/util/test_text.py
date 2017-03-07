from nose.tools import assert_raises

from mediawords.util.text import *


def test_random_string():
    assert_raises(McRandomStringException, random_string, 0)
    assert_raises(McRandomStringException, random_string, -1)

    length = 16
    string_1 = random_string(length=length)
    string_2 = random_string(length=length)

    assert string_1 != string_2
    assert len(string_1) == length
    assert len(string_2) == length
    assert string_1.isalnum()
    assert string_2.isalnum()
