from collections import namedtuple
from enum import Enum, IntEnum

LOCALE = 'en'


class Accuracy(IntEnum):
    """Mark how accurate a publishing date guess is"""
    NONE = 0  # No guess at all
    PARTIAL = 1  # Some data gathered, might be missing a day
    DATE = 2  # Has ~date level accuracy, might be +/- 1 day
    DATETIME = 3  # Has datetime level accuracy, ~1ms


NO_METHOD = 'Did not find anything'

Guess = namedtuple('Guess', ('date', 'accuracy', 'method'))
