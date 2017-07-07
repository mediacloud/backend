import random
import re
import string


class McRandomStringException(Exception):
    """random_string() exception."""


def random_string(length: int) -> str:
    """Generate random, not crypto-secure alphanumeric string of the specified length."""
    # FIXME replace with "secrets" module after upgrading to Python 3.6
    if length < 1:
        raise McRandomStringException("Length must be >=1.")

    chars = string.ascii_letters + string.digits
    r = random.SystemRandom()
    rand_str = ''.join(r.choice(chars) for _ in range(length))
    return rand_str


def is_punctuation(parsed_token: str) -> bool:
    result = re.sub(u"[\p{P}\p{InHalfwidth_and_Fullwidth_Forms}\p{InCJK_Symbols_and_Punctuation}]+", "", parsed_token)
    if not result:  # if result is not empty, i.e. it is not replaced with "", it is not a punctuation
        return False
    else:
        return True
