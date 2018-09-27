# MC_REWRITE_TO_PYTHON: try renaming back to .util.json

import json
from typing import Union, Dict, List

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McJSONException(Exception):
    """JSON encoding / decoding exception."""
    pass


class McEncodeJSONException(McJSONException):
    """encode_json() exception."""
    pass


class McDecodeJSONException(McJSONException):
    """decode_json() exception."""
    pass


def encode_json(json_obj: Union[Dict, List], pretty: bool = False) -> str:
    """Encode dictionary or list to JSON."""

    json_obj = decode_object_from_bytes_if_needed(json_obj)

    if not (isinstance(json_obj, dict) or isinstance(json_obj, list)):
        raise McEncodeJSONException("Object is neither a dictionary nor a list: %s" % (str(json_obj),))

    indent = None  # most compact representation
    if pretty:
        indent = 4

    try:
        json_string = json.dumps(json_obj, indent=indent, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
    except Exception as ex:
        raise McEncodeJSONException("Unable to encode object %s to JSON: %s" % (str(json_obj), str(ex),))

    if json_string is None:
        raise McEncodeJSONException("Resulting JSON string is None for object: %s" % (str(json_obj),))

    if len(json_string) == 0:
        raise McEncodeJSONException("Resulting JSON string is empty for object: %s" % (str(json_obj),))

    return json_string


def decode_json(json_string: str) -> Union[Dict, List]:
    """Decode JSON to dictionary or list."""

    json_string = decode_object_from_bytes_if_needed(json_string)

    if json_string is None:
        raise McDecodeJSONException("JSON string is None.")

    if len(json_string) == 0:
        raise McDecodeJSONException("JSON string is empty.")

    try:
        json_obj = json.loads(json_string)
    except Exception as ex:
        raise McDecodeJSONException("Unable to decode string %s from JSON: %s" % (str(json_string), str(ex)))

    if json_obj is None:
        raise McEncodeJSONException("Resulting JSON object is None for string: %s" % (str(json_string),))

    return json_obj
