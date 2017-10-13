from datetime import datetime

import pytz

from mediawords.date_guesser import DateGuesser
from mediawords.date_guesser.constants import Accuracy


class TestDateGuesser(object):
    def setup_method(self):
        self.parser = DateGuesser()

    def test_parse_nyt(self):
        url = 'https://www.nytimes.com/2017/10/13/opinion/catalonia-spain-puigdemont.html'
        html = '<could be anything></could>'

        parsed_date, accuracy = self.parser.guess_date(url, html)
        assert parsed_date == datetime(2017, 10, 13, tzinfo=pytz.utc)
        assert accuracy is Accuracy.DATE

        html = '''
        <html><head>
        <meta property="article:published"
              itemprop="datePublished"
              content="2017-10-13T04:56:54-04:00" />
         </head></html>
         '''
        parsed_date, accuracy = self.parser.guess_date(url, html)
        assert parsed_date == datetime(2017, 10, 13, 8, 56, 54, tzinfo=pytz.utc)
        assert accuracy is Accuracy.DATETIME

