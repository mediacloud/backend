"""Test crimson_hexagon_twitter.py"""

import os

from topics_mine.posts.crimson_hexagon_twitter import CrimsonHexagonTwitterPostFetcher

# these keys need dummry values to prevent errors
DUMMY_KEYS = [
        'MC_CRIMSON_HEXAGON_API_KEY',
        'MC_TWITTER_CONSUMER_KEY',
        'MC_TWITTER_CONSUMER_SECRET',
        'MC_TWITTER_ACCESS_TOKEN',
        'MC_TWITTER_ACCESS_TOKEN_SECRET']

def test_fetch_posts() -> None:
    """Test fetch_posts."""
    for k in DUMMY_KEYS:
        os.environ[k] = 'foo'

    CrimsonHexagonTwitterPostFetcher().test_mock_data(query='123')
