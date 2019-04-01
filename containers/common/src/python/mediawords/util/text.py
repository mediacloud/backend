import random
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
