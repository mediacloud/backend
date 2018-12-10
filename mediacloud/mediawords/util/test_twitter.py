"""Unit tests for mediawords.util.twitter."""

import os
import unittest

import mediawords.util.config
import mediawords.util.twitter

MIN_TEST_TWEET_LENGTH = 10
MIN_TEST_TWITTER_USER_LENGTH = 3


@unittest.skipUnless(os.environ.get('MC_REMOTE_TESTS', False), "remote tests")
def test_twitter_api() -> None:
    """Test Twitter.fetch_100_tweets() by hitting the remote twitter api."""
    config = mediawords.util.config.get_config()

    assert 'twitter' in config, "twitter section present in mediawords.yml"
    for key in 'consumer_key consumer_secret access_token access_token_secret'.split():
        assert key in config['twitter'], "twitter." + key + " present in mediawords.yml"

    test_status_id = '915261573597364224'
    got_tweets = mediawords.util.twitter.fetch_100_tweets([test_status_id])

    assert len(got_tweets) == 1

    got_tweet = got_tweets[0]

    assert 'text' in got_tweet
    assert len(got_tweet['text']) > MIN_TEST_TWEET_LENGTH
    assert 'user' in got_tweet
    assert 'screen_name' in got_tweet['user']
    assert len(got_tweet['user']['screen_name']) > MIN_TEST_TWITTER_USER_LENGTH
