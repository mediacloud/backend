import random
import re
import string as py_string


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


def replace_control_nonprintable_characters(string: str, replacement: str = ' ') -> str:
    """Remove ASCII control characters except for \n, \r, and \t."""

    # Allow 0x09 CHARACTER TABULATION
    # Allow 0x0a LINE FEED (LF)
    # Allow 0x0d CARRIAGE RETURN (CR)
    string = re.sub(r'[\x00-\x08\x0b-\x0c\x0e-\x1f\x7f-\x9f]', replacement, string)

    return string
