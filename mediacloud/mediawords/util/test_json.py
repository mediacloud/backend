import pytest

from mediawords.util.json import (encode_json, decode_json, McDecodeJSONException,
                                  McEncodeJSONException)


def test_encode_decode_json():
    test_obj = [
        'foo',
        {'bar': 'baz'},
        ['xyz', 'zyx'],
        'moo',
        'ąčęėįšųūž',
        42,
        3.14,
        True,
        False,
        None
    ]
    expected_json = '["foo",{"bar":"baz"},["xyz","zyx"],"moo","ąčęėįšųūž",42,3.14,true,false,null]'

    encoded_json = encode_json(json_obj=test_obj, pretty=False)
    assert encoded_json == expected_json

    decoded_json = decode_json(json_string=encoded_json)
    assert decoded_json == test_obj

    # Encoding errors
    with pytest.raises(McEncodeJSONException):
        # noinspection PyTypeChecker
        encode_json(None)

    with pytest.raises(McEncodeJSONException):
        # noinspection PyTypeChecker
        encode_json("strings can't be encoded")

    with pytest.raises(McDecodeJSONException):
        # noinspection PyTypeChecker
        decode_json(None)

    with pytest.raises(McDecodeJSONException):
        # noinspection PyTypeChecker
        decode_json('not JSON')
