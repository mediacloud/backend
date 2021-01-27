#!/usr/bin/env python3

import datetime
import dateutil.parser
import pytz
import re
import statistics
from typing import Optional

import mediawords.db
import topics_mine.fetch_topic_posts

from mediawords.util.log import create_logger

log = create_logger(__name__)


def run_single_platform_test(source, platform, query, pattern, day, min_posts: int, max_posts: Optional[int] = None, sample: Optional[int] = None) -> None:
    """Run test for a single platform / source.""" 
    fetcher = topics_mine.fetch_topic_posts.get_post_fetcher({'source': source, 'platform': platform})
    assert fetcher, "%s %s fetcher exists" % (source, platform)

    start_date = dateutil.parser.parse(day)
    end_date = start_date + datetime.timedelta(days=1) - datetime.timedelta(seconds=1) 

    got_posts = fetcher.fetch_posts(query=query, start_date=start_date, end_date=end_date, sample=sample)

    assert len(got_posts) >= min_posts
    if max_posts is not None:
        assert len(got_posts) <= max_posts

    # allow for timezone skew from source
    got_start_date = (start_date - datetime.timedelta(hours=12)).replace(tzinfo=None)
    got_end_date = (end_date + datetime.timedelta(hours=12)).replace(tzinfo=None)

    for got_post in got_posts:
        publish_date = dateutil.parser.parse(got_post['publish_date']).replace(tzinfo=None)
        assert publish_date >= got_start_date and publish_date <= got_end_date
        assert re.search(pattern, got_post['content'], re.I)
        assert len(got_post['content']) > 0
        assert len(got_post['author']) > 0
        assert len(got_post['channel']) > 0
        assert len(got_post['data']) > 0

    assert len(set([p['content'] for p in got_posts])) > len(got_posts) / 10
    assert len(set([p['author'] for p in got_posts])) > len(got_posts) / 10
    assert len(set([p['channel'] for p in got_posts])) > len(got_posts) / 100

    assert statistics.mean([len(p['content']) for p in got_posts]) > 80


def test_brandwatch_twitter() -> None:
    run_single_platform_test(
            source='brandwatch',
            platform='twitter',
            query='1998295792-2000353908',
            pattern='.*',
            day='2020-08-17',
            min_posts=1000,
            sample=1000,
        )


def test_crimson_hexagon_twitter() -> None:
    run_single_platform_test(
            source='crimson_hexagon',
            platform='twitter',
            query=32780805819,
            pattern='.*',
            day='2017-08-17',
            min_posts=400,
        )


def test_pushshift_reddit() -> None:
    run_single_platform_test(
            source='pushshift',
            platform='reddit',
            query='trump',
            pattern='trump',
            day='2020-01-01',
            min_posts=1000,
        )
