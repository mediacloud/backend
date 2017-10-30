import datetime
import os

import pytz

from mediawords.date_guesser.constants import Accuracy, NO_METHOD
from mediawords.date_guesser.urls import (parse_url_for_date, url_date_generator,
                                          filter_url_for_undateable)


TEST_DIR = os.path.abspath(os.path.dirname(__file__))



def test_url_date_generator():
    string_with_matches = '/2013/12/17/20140109/01_09_1985-02-05'
    for captures, method in url_date_generator(string_with_matches):
        for key in ('year', 'month', 'day'):
            assert key in captures


def test_parse_urls_with_date():
    test_urls = (
        ('2013-12-17', 'http://www.cnn.com/2013/12/17/politics/senate/index.html?hpt=hp_t1'),
        ('2013-12-17', 'http://www.cnn.com/12/17/2013/politics/senate/index.html?hpt=hp_t1'),
        ('2013-12-16', 'http://www.news.com/20131216/beyonce-album_n_4453500.html'),
        ('2012-02-29', 'http://www.news.com/Feb/29/2012/beyonce-album_n_4453500.html'),
    )
    for date_str, url in test_urls:
        date = datetime.datetime.strptime(date_str, '%Y-%m-%d').replace(tzinfo=pytz.utc)
        guess = parse_url_for_date(url)
        assert guess.date == date
        assert guess.accuracy is Accuracy.DATE
        assert 'url' in guess.method


def test_parse_urls_with_partial_date():
    test_urls = (
        ('2015-10-15', 'http://www.news.com/local/2015/10/jim_webb'),
        ('2016-2-15', 'http://news.org/1/files/2016-02/ohio-FY2014-15-budget.pdf#page=5'),
        ('2013-09-15', 'http://www.news.com/sept/2013/beyonce-album_n_4453500.html'),
        ('2013-01-15', 'http://www.news.com/2013/jan/beyonce-album_n_4453500.html'),
    )
    for date_str, url in test_urls:
        date = datetime.datetime.strptime(date_str, '%Y-%m-%d').replace(tzinfo=pytz.utc)
        guess = parse_url_for_date(url)
        assert guess.date == date
        assert guess.accuracy is Accuracy.PARTIAL
        assert 'url' in guess.method


def test_parse_tricky_urls():
    test_urls_no_date = (
        'http://chriskeniston2016.com/3385-2/',  # 2016.com parses as 'YEAR.month'
        'http://www.news.co/libro-198781',  # if this ends in '199781', parses to 08/01/1997
        'http://www.news.co/libro-205081',
        'http://www.news.co/libro-201008012',  # the extra '2' means not '08/01/2010'
        'http://www.news.com/2013/13/22/beyonce-album_n_4453500.html',  # 13 months?
        'http://www.news.com/2013/01/32/beyonce-album_n_4453500.html',  # 32 days?
        'http://www.news.com/2013/02/29/beyonce-album_n_4453500.html',  # 2013 not a leap year
    )
    for url in test_urls_no_date:
        guess = parse_url_for_date(url)
        assert guess.date is None
        assert guess.accuracy is Accuracy.NONE
        assert guess.method is NO_METHOD

def test_filter_url_for_undateable():
    test_urls_undateable = (
        '/foo/bar/baz.html',  # no hostname
        'https://new.project.in.en.wikipedia.org/other_stuff',  # any wikipedia subdomain
        'https://twitter.com/',  # twitter homepage
        'https://mobile.twitter.com/nytimes',  # twitter user feeds
        'https://twitter.com/hashtag/MITLegalForum',  # twitter hashtag feeds
        'https://foo.bar.com/',  # any front page
        'https://www.google.es/search?q=chocolate',  # search terms
        'http://www.medianama.com/tag/aadhaar-act',  # tag pages
    )

    for url in test_urls_undateable:
        guess = filter_url_for_undateable(url)
        assert not (guess is None)
        assert guess.date is None
        assert guess.accuracy is Accuracy.NONE
