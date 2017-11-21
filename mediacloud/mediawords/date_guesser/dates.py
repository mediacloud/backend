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
        DateFormat('YYYY-MM-DD', Accuracy.DATE),
        DateFormat('ddd MMM DD HH:mm:ss [PDT] YYYY', Accuracy.DATETIME),
        DateFormat('MMM DD, YYYY, HH.mm A', Accuracy.DATETIME),
        DateFormat('dddd, DD MMMM, YYYY HH:mm:ss', Accuracy.DATETIME),
        DateFormat('YYYY-M-D H:m:s', Accuracy.DATETIME),
        DateFormat('H:mm A - D MMM YYYY', Accuracy.DATETIME),
        DateFormat('MMM D, YYYY', Accuracy.DATE),
        DateFormat('MMM. D, YYYY', Accuracy.DATE),
        DateFormat('MMMM D, YYYY', Accuracy.DATE),
        DateFormat('MMMM YYYY', Accuracy.PARTIAL),
        )

    def __init__(self, parser):
        """Wrap an arrow.parser.DateTimeParser with some custom operations."""
        self.parser = parser

    def _try_format(self, date_string, date_format):
        try:
            parsed_date = self.parser.parse(date_string, fmt=date_format.format)
        except arrow.parser.ParserError:
            return None, Accuracy.NONE
        if parsed_date.tzinfo is None:
            parsed_date = parsed_date.replace(tzinfo=pytz.utc)
        return parsed_date, date_format.accuracy

    def iter_matches(self, date_string, fmts=None):
        if date_string is None:
            return
        if fmts is None:
            fmts = self.formats
        for date_format in fmts:
            yield self._try_format(date_string, date_format)

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
        for new_date, new_accuracy in self.iter_matches(date_string, fmts=fmts):
            if new_accuracy > accuracy:
                parsed_date, accuracy = new_date, new_accuracy
        return parsed_date, accuracy
