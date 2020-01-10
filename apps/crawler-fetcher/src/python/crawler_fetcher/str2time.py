import time
from typing import Optional

from dateutil.parser import parse as parse_date

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def str2time_21st_century(date: str) -> Optional[int]:
    """Converts date string to timestamp; treats "61" as 2061, not 1961."""

    # In Perl, the str2time() would sometimes decide that "61" is 1961, not 2016, which is not the case with Python's
    # dateutil.parser.parse(). However, we still keep this helper (together with the test) around to emphasize the need
    # to parse such dates correctly.

    date = decode_object_from_bytes_if_needed(date)
    if not date:
        log.error("Date is unset")
        return None

    try:
        guessed_dt = parse_date(date)
    except Exception as ex:
        log.error(f"Unable to parse date '{date}': {ex}")
        return None

    if not guessed_dt:
        log.error(f"Parsed date is unset: {date}")
        return None

    timestamp = time.mktime(guessed_dt.timetuple())

    return int(timestamp)
