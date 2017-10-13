from collections import namedtuple

import arrow
import pytz

from .constants import Accuracy

DateFormat = namedtuple('DateFormat', 'format accuracy')


class MultiDateParser(object):
    formats = (
        DateFormat('YYYY-MM-DDTHH:mm:ssZZ', Accuracy.DATETIME),
        DateFormat('ddd MMM DD HH:mm:ss ZZZ YYYY', Accuracy.DATETIME),
        DateFormat('YYYY-MM-DDZZZhh:mm', Accuracy.DATETIME),
        DateFormat('MM/DD/YYYY HH:mm:ss ZZZ', Accuracy.DATETIME),
    )

    def __init__(self, parser):
        """Wrap an arrow.parser.DateTimeParser with some custom operations."""
        self.parser = parser

    def parse(self, date_string, fmts=None):
        """Convert a datestring into a python datetime, using self.formats, in order.

        Attributes
        ----------
        date_string : str or None
            string to be parsed
        fmts : iterable of DateFormat (default: MultiDateParser.formats)

        Returns
        -------
        (datetime.datetime or None, Accuracy)
        """
        parsed_date = None
        accuracy = Accuracy.NONE
        if date_string is not None:
            if fmts is None:
                fmts = self.formats
            for date_format in fmts:
                if date_format.accuracy > accuracy:
                    try:
                        parsed_date = self.parser.parse(date_string, fmt=date_format.format)
                    except arrow.parser.ParserError:
                        continue
                    if parsed_date.tzinfo is None:
                        parsed_date = parsed_date.replace(tzinfo=pytz.utc)
                    accuracy = date_format.accuracy
        return parsed_date, accuracy
