import datetime
from typing import Union

from date_guesser import guess_date as mit_guess_date, Accuracy
import pytz

from mediawords.util.perl import decode_object_from_bytes_if_needed

# tag set and tag names for guess method
GUESS_METHOD_TAG_SET = 'date_guess_method'
INVALID_TAG_SET = 'date_invalid'
INVALID_TAG = 'date_invalid'


class GuessDateResult(object):
    __slots__ = [
        '__found',
        '__guess_method',
        '__timestamp',
    ]

    def __init__(self, found: bool, guess_method: str = None, timestamp: int = None):
        self.__found = found
        self.__guess_method = guess_method
        self.__timestamp = timestamp

    @property
    def found(self) -> bool:
        """Whether the date was found in the URL."""
        return self.__found

    @property
    def guess_method(self) -> Union[str, None]:
        """Free-form date guessing method used (string), if applicable."""
        return self.__guess_method

    @property
    def timestamp(self) -> Union[int, None]:
        """Date UNIX timestamp / epoch (integer), if applicable."""
        return self.__timestamp

    @property
    def date(self) -> Union[str, None]:
        """String date, ISO-8601 string in GMT timezone (e.g. '2012-01-17T17:00:00'), if applicable."""
        if self.timestamp is None:
            return None
        else:
            return datetime.datetime.utcfromtimestamp(self.timestamp).strftime('%Y-%m-%dT%H:%M:%S')


class McGuessDateException(Exception):
    """guess_date() exception."""
    pass


def guess_date(url: str, html: str) -> GuessDateResult:
    """Guess the date for the story."""
    if url is None:
        raise McGuessDateException("URL is None.")
    if html is None:
        raise McGuessDateException("HTML is None.")

    url = decode_object_from_bytes_if_needed(url)
    html = decode_object_from_bytes_if_needed(html)

    try:
        guess = mit_guess_date(url=url, html=html)
    except Exception as ex:
        raise McGuessDateException("Guess date failed: %s" % str(ex))

    if guess.accuracy is Accuracy.NONE:
        return GuessDateResult(found=False)

    else:
        timestamp = int((guess.date - datetime.datetime(1970, 1, 1, tzinfo=pytz.utc)) / datetime.timedelta(seconds=1))
        return GuessDateResult(found=True, guess_method=guess.method, timestamp=timestamp)
