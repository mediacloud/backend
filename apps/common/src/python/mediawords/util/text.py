import random
import string as py_string
from typing import Any


class McRandomStringException(Exception):
    """random_string() exception."""


def random_string(length: int) -> str:
    """Generate random, not crypto-secure alphanumeric string of the specified length."""
    # FIXME replace with "secrets" module after upgrading to Python 3.6
    if length < 1:
        raise McRandomStringException("Length must be >=1.")

    chars = py_string.ascii_letters + py_string.digits
    r = random.SystemRandom()
    rand_str = ''.join(r.choice(chars) for _ in range(length))
    return rand_str


def escape_for_repr(value: Any) -> str:
    """
    Escape value for returning in __repr__().

    :param value: Value to escape.
    :return: Escaped value usable in __repr__().
    """

    # FIXME probably not too secure, plus not every Python type is supported here

    if value is None:
        value = 'None'
    else:
        if isinstance(value, str):
            value = value.replace("'", "\\'")
            value = "'" + value + "'"
        elif isinstance(value, int) or isinstance(value, float):
            value = str(value)
        else:
            value = value.__repr__()

    return value
