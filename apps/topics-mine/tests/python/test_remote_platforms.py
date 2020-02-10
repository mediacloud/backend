#!/usr/bin/env python3

import datetime
import dateutil.parser
import pytz
import re

import mediawords.db

from topics_mine.posts.crimson_hexagon_twitter import CrimsonHexagonTwitterPostFetcher
from topics_mine.posts.pushshift_reddit import PushshiftRedditPostFetcher

from mediawords.util.log import create_logger

log = create_logger(__name__)

TEST_DEFINITIONS =\
    [
        {
            'class': CrimsonHexagonTwitterPostFetcher,
            'query': 32780805819,
            'pattern': '.*', # CH searches through non-content metadata for pattern matches
            'day': '2017-08-17',
            'min_posts': 400,
            'max_posts': 500
        },
        {
            'class': PushshiftRedditPostFetcher,
            'query': 'trump',
            'pattern': 'trump',
            'day': '2020-01-01',
            'min_posts': 1000,
            'max_posts': 3000
        }
    ]

def run_single_platform_test(test: dict) -> None:
    """Run test for a single platform / source as definite in TEST_DEFINITIONS."""
    fetcher = test['class']()

    start_date = dateutil.parser.parse(test['day'])
    end_date = start_date + datetime.timedelta(days=1) - datetime.timedelta(seconds=1) 

    got_posts = fetcher.fetch_posts(query=test['query'], start_date=start_date, end_date=end_date)

    assert len(got_posts) >= test['min_posts'] and len(got_posts) <= test['max_posts'], test['class']

    # allow for timezone skew from source
    got_start_date = (start_date - datetime.timedelta(hours=12)).replace(tzinfo=None)
    got_end_date = (end_date + datetime.timedelta(hours=12)).replace(tzinfo=None)

    for got_post in got_posts:
        publish_date = dateutil.parser.parse(got_post['publish_date']).replace(tzinfo=None)
        assert publish_date >= got_start_date and publish_date <= got_end_date
        assert re.search(test['pattern'], got_post['content'], re.I)


def test_remote_platforms() -> None:
    """Test each remote platform / source combination."""

    for test in TEST_DEFINITIONS:
        log.info("testing %s" % test['class'])
        run_single_platform_test(test)
