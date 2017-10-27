from datetime import datetime

import pytz

from mediawords.date_guesser import DateGuesser
from mediawords.date_guesser.constants import Accuracy, NO_METHOD


class TestDateGuesser(object):
    def setup_method(self):
        self.parser = DateGuesser()

    def test_parse_nonsense(self):
        # Should find nothing here
        url = 'https://www.nytimes.com/opinion/catalonia-spain-puigdemont.html'
        html = '<could be anything></could>'

        guess = self.parser.guess_date(url, html)
        assert guess.date is None
        assert guess.accuracy is Accuracy.NONE
        assert guess.method is NO_METHOD

    def test_parse_nyt(self):
        url = 'https://www.nytimes.com/2017/10/13/opinion/catalonia-spain-puigdemont.html'
        html = '<could be anything></could>'

        guess = self.parser.guess_date(url, html)
        assert guess.date == datetime(2017, 10, 13, tzinfo=pytz.utc)
        assert guess.accuracy is Accuracy.DATE
        assert '2017/10/13' in guess.method

        html = '''
        <html><head>
        <meta property="article:published"
              itemprop="datePublished"
              content="2017-10-13T04:56:54-04:00" />
         </head></html>
         '''
        guess = self.parser.guess_date(url, html)
        assert guess.date == datetime(2017, 10, 13, 8, 56, 54, tzinfo=pytz.utc)
        assert guess.accuracy is Accuracy.DATETIME
        assert '2017-10-13T04:56:54-04:00' in guess.method
