from datetime import datetime

from arrow.parser import DateTimeParser
import pytz

from mediawords.date_guesser.constants import Accuracy
from mediawords.date_guesser.dates import DateFormat, MultiDateParser


class TestMultiDateParser(object):
    def setup_method(self):
        self.parser = DateTimeParser(locale='en')
        self.multi_parser = MultiDateParser(self.parser)

    def test_parse_none(self):
        parsed_date, accuracy = self.multi_parser.parse(None)
        assert parsed_date is None
        assert accuracy is Accuracy.NONE

    def test_parse(self):
        self.multi_parser.formats = (DateFormat('YYYY-MM-DD', Accuracy.DATE),)
        parsed_date, accuracy = self.multi_parser.parse('1985-01-09')
        assert parsed_date == datetime(1985, 1, 9, tzinfo=pytz.utc)
        assert accuracy is Accuracy.DATE

    def test_parse_iso(self):
        iso_date = '2017-10-13T12:18:24+00:00'

        # should always handle ISO by default
        parsed_date, accuracy = self.multi_parser.parse(iso_date)
        assert parsed_date == datetime(2017, 10, 13, 12, 18, 24, tzinfo=pytz.utc)
        assert accuracy is accuracy.DATETIME

    def test_multiple_formats(self):
        self.multi_parser.formats = (
            DateFormat('YYYY-MM-DD', Accuracy.DATE),
            DateFormat('YYYY-MM-DD HH:mm', Accuracy.DATETIME),
        )
        test_cases = (
            ('2017-10-13', (datetime(2017, 10, 13, tzinfo=pytz.utc), Accuracy.DATE)),
            ('2017-10-13 01:23', (datetime(2017, 10, 13, 1, 23, tzinfo=pytz.utc),
                                 Accuracy.DATETIME)),
            ('2017-10-13T12:18:24+00:00', (datetime(2017, 10, 13, tzinfo=pytz.utc), Accuracy.DATE))
        )

        for test_case, (expected_datetime, expected_accuracy) in test_cases:
            parsed_date, accuracy = self.multi_parser.parse(test_case)
            assert parsed_date == expected_datetime
            assert accuracy is expected_accuracy
