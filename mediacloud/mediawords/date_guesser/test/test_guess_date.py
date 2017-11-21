from datetime import datetime

from bs4 import BeautifulSoup
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

    def test_guess_date_from_image_tag(self):
        html = '''
        <html><head>
        <meta property="og:image" content="foo.com/2017/10/13/whatever.jpg"/>
         </head></html>
        '''
        soup = BeautifulSoup(html, 'lxml')
        guess = self.parser.guess_date_from_image_tag(soup)
        assert guess.date == datetime(2017, 10, 13, tzinfo=pytz.utc)
        assert guess.accuracy is Accuracy.DATE
        assert '2017/10/13' in guess.method
        assert 'tag' in guess.method

    def test_use_more_useful_data(self):
        # main url is a year after image url
        url = 'https://www.nytimes.com/2017/10/opinion/catalonia-spain-puigdemont.html'
        html = '''
        <html><head>
        <meta property="og:image" content="foo.com/2017/10/13/whatever.jpg"/>
         </head></html>
        '''
        guess = self.parser.guess_date(url, html)
        assert guess.date == datetime(2017, 10, 13, tzinfo=pytz.utc)
        assert guess.accuracy is Accuracy.DATE
        assert '2017/10/13' in guess.method

    def test_ignore_less_useful_data(self):
        # main url is a year after image url
        url = 'https://www.nytimes.com/2018/10/opinion/catalonia-spain-puigdemont.html'
        html = '''
        <html><head>
        <meta property="og:image" content="foo.com/2017/10/13/whatever.jpg"/>
         </head></html>
        '''
        guess = self.parser.guess_date(url, html)
        assert guess.date == datetime(2018, 10, 15, tzinfo=pytz.utc)
        assert guess.accuracy is Accuracy.PARTIAL
        assert '2018/10' in guess.method

    def test_ignore_wikipedia(self):
        url = 'https://en.wikipedia.org/2018/10/13/opinion/catalonia-spain-puigdemont.html'
        html = '''
        <html><head>
        <meta property="og:image" content="foo.com/2017/10/13/whatever.jpg"/>
         </head></html>
        '''
        guess = self.parser.guess_date(url, html)
        assert guess.date is None
        assert guess.accuracy is Accuracy.NONE
        assert 'No date' in guess.method
