"""Test brandwatch_twitter.py"""

import os

from topics_mine.posts.brandwatch_twitter import BrandwatchTwitterPostFetcher

# these keys need dummry values to prevent errors
DUMMY_KEYS = [
        'MC_BRANDWATCH_USER',
        'MC_BRANDWATCH_PASSWORD',
        'MC_TWITTER_CONSUMER_KEY',
        'MC_TWITTER_CONSUMER_SECRET',
        'MC_TWITTER_ACCESS_TOKEN',
        'MC_TWITTER_ACCESS_TOKEN_SECRET']

def test_fetch_posts() -> None:
    """Test fetch_posts."""
    for k in DUMMY_KEYS:
        os.environ[k] = 'foo'

    BrandwatchTwitterPostFetcher().test_mock_data(query='123-456')
