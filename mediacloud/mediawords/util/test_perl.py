from mediawords.util.perl import *


def test_decode_string_from_bytes_if_needed():
    assert decode_string_from_bytes_if_needed(b'foo') == 'foo'
    assert decode_string_from_bytes_if_needed('foo') == 'foo'
    assert decode_string_from_bytes_if_needed(42) == 42
    assert decode_string_from_bytes_if_needed(None) is None


def test_object_from_bytes_if_needed():
    input_obj = {
        b'a': b'b',
        b'c': [
            b'd',
            b'e',
            b'f',
        ],
        b'g': {
            b'h': {
                b'i': 42,
                'j': None,
            }
        }
    }
    expected = {
        'a': 'b',
        'c': [
            'd',
            'e',
            'f',
        ],
        'g': {
            'h': {
                'i': 42,
                'j': None,
            }
        }
    }
    got = decode_object_from_bytes_if_needed(input_obj)
    assert expected == got
