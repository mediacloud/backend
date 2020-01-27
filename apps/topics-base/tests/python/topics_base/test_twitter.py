"""Unit tests for mediawords.util.twitter."""

import requests_mock

import topics_base.twitter as twitter

from mediawords.util.log import create_logger

log = create_logger(__name__)

def test_fetch_100_users() -> None:
    """Test fetch_100_tweets using mock."""
    with requests_mock.Mocker() as m:
        twitter.add_mockers(m)
        got_users = twitter.fetch_100_users(['foo', 'bar', 'bat'])

    got_screen_names = [u['screen_name'] for u in got_users]

    assert sorted(got_screen_names) == ['bar', 'bat', 'foo']


def test_fetch_100_tweets() -> None:
    """Test fetch_100_tweets using mock."""
    fetch_ids = range(100)

    with requests_mock.Mocker() as m:
        twitter.add_mockers(m)
        got_tweets = twitter.fetch_100_tweets(fetch_ids)

    got_tweets = sorted(got_tweets, key=lambda t: int(t['id_str']))

    for (i, tweet) in enumerate(got_tweets):
        assert(tweet['id_str'] == str(i))
        assert(tweet['text'] == 'content %d' % i)
