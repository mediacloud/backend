"""Test csv_generic.py"""

import datetime
import dateutil

# noinspection PyProtectedMember
from topics_mine.posts.csv_generic import CSVStaticPostFetcher

from mediawords.util.log import create_logger

log = create_logger(__name__)

def test_fetch_posts() -> None:
    """Test fetch_posts."""
    csv_fetcher = CSVStaticPostFetcher()

    csv_fetcher.enable_mock()

    expected_posts = csv_fetcher.get_mock_data()

    start_date = dateutil.parser.parse(expected_posts[0]['publish_date'])
    end_date = dateutil.parser.parse(expected_posts[-1]['publish_date'])

    got_posts = csv_fetcher.fetch_posts('', start_date, end_date)

    assert len(got_posts) == len(expected_posts)
    for i, got_post in enumerate(got_posts):
        for field in ('post_id', 'author', 'channel', 'content'):
            assert got_post[field] == expected_posts[i][field]

    # got_posts = csv_fetcher.fetch_posts(posts_csv, start_date, start_date)

    # assert len(got_posts) == 1
    # assert got_posts[0]['post_id'] == '0'
