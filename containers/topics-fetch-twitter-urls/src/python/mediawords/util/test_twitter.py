"""Unit tests for mediawords.util.twitter."""

import json
import os
from typing import List
from urllib.parse import urlparse, parse_qs
import unittest

import httpretty

import mediawords.util.config
import mediawords.util.twitter as mut

MIN_TEST_TWEET_LENGTH = 10
MIN_TEST_TWITTER_USER_LENGTH = 3


@unittest.skipUnless(os.environ.get('MC_REMOTE_TESTS', False), "remote tests")
def test_fetch_100_users_remote() -> None:
    """Test Twitter.fetch_100_users() by hitting the remote twitter api."""
    config = mediawords.util.config.get_config()

    assert 'twitter' in config, "twitter section present in mediawords.yml"
    for key in 'consumer_key consumer_secret access_token access_token_secret'.split():
        assert key in config['twitter'], "twitter." + key + " present in mediawords.yml"

    screen_name = 'cyberhalroberts'
    got_users = mut.fetch_100_users([screen_name])

    assert len(got_users) == 1

    got_user = got_users[0]

    assert got_user['screen_name'] == 'cyberhalroberts'
    assert got_user['name'] == 'Hal Roberts'
    assert got_user['id'] == 38100863


@unittest.skipUnless(os.environ.get('MC_REMOTE_TESTS', False), "remote tests")
def test_fetch_100_tweets_remote() -> None:
    """Test Twitter.fetch_100_tweets() by hitting the remote twitter api."""
    config = mediawords.util.config.get_config()

    assert 'twitter' in config, "twitter section present in mediawords.yml"
    for key in 'consumer_key consumer_secret access_token access_token_secret'.split():
        assert key in config['twitter'], "twitter." + key + " present in mediawords.yml"

    test_status_id = '915261573597364224'
    got_tweets = mut.fetch_100_tweets([test_status_id])

    assert len(got_tweets) == 1

    got_tweet = got_tweets[0]

    assert 'text' in got_tweet
    assert len(got_tweet['text']) > MIN_TEST_TWEET_LENGTH
    assert 'user' in got_tweet
    assert 'screen_name' in got_tweet['user']
    assert len(got_tweet['user']['screen_name']) > MIN_TEST_TWITTER_USER_LENGTH


def _mock_users_lookup(request, uri, response_headers) -> List:
    """Mock twitter /statuses/lookup response."""
    params = parse_qs(request.body.decode('utf-8'))

    screen_names = params['screen_name'][0].split(',')

    users = []
    for i, screen_name in enumerate(screen_names):
        user = {
            'id': str(i),
            'name': 'user %d' % i,
            'screen_name': screen_name,
            'description': "test description for user %d" % i}
        users.append(user)

    return [200, response_headers, json.dumps(users)]


def test_fetch_100_users() -> None:
    """Test fetch_100_tweets using mock."""
    httpretty.enable()
    httpretty.register_uri(
        httpretty.POST, "https://api.twitter.com/1.1/users/lookup.json", body=_mock_users_lookup)

    got_users = mut.fetch_100_users(['foo', 'bar', 'bat'])

    got_screen_names = [u['screen_name'] for u in got_users]

    assert sorted(got_screen_names) == ['bar', 'bat', 'foo']

    httpretty.disable()
    httpretty.reset()


def _mock_statuses_lookup(request, uri, response_headers) -> List:
    """Mock twitter /statuses/lookup response."""
    params = parse_qs(urlparse(uri).query)

    ids = params['id'][0].split(',')

    json = ','.join(['{"id": %s, "text": "content %s"}' % (id, id) for id in ids])

    json = '[%s]' % json

    return [200, response_headers, json]


def test_fetch_100_tweets() -> None:
    """Test fetch_100_tweets using mock."""
    httpretty.enable()
    httpretty.register_uri(
        httpretty.GET, "https://api.twitter.com/1.1/statuses/lookup.json", body=_mock_statuses_lookup)

    got_tweets = mut.fetch_100_tweets([1, 2, 3, 4])

    assert sorted(got_tweets, key=lambda t: t['id']) == [
        {'id': 1, 'text': "content 1"},
        {'id': 2, 'text': "content 2"},
        {'id': 3, 'text': "content 3"},
        {'id': 4, 'text': "content 4"}]

    httpretty.disable()
    httpretty.reset()


def test_parse_status_id_from_url() -> None:
    "Test parse_status_id_from_url()."
    assert mut.parse_status_id_from_url('https://twitter.com/jwood/status/557722370597978115') == '557722370597978115'
    assert mut.parse_status_id_from_url('http://twitter.com/srhbus/status/586418382515208192') == '586418382515208192'
    assert mut.parse_status_id_from_url('http://twitter.com/srhbus/status/12345?foo=bar') == '12345'
    assert mut.parse_status_id_from_url('http://google.com') is None
    assert mut.parse_status_id_from_url('http://twitter.com/jeneps') is None


def test_parse_screen_name_from_user_url() -> None:
    "Test parse_status_id_from_url()."
    assert mut.parse_screen_name_from_user_url('https://twitter.com/jwoodham/status/557722370597978115') is None
    assert mut.parse_screen_name_from_user_url('http://twitter.com/BookTaster') == 'BookTaster'
    assert mut.parse_screen_name_from_user_url('https://twitter.com/tarantallegra') == 'tarantallegra'
    assert mut.parse_screen_name_from_user_url('https://twitter.com/tarantallegra?foo=bar') == 'tarantallegra'
    assert mut.parse_screen_name_from_user_url('https://twitter.com/search?q=foo') is None
    assert mut.parse_screen_name_from_user_url('https://twitter.com/login?q=foo') is None
    assert mut.parse_screen_name_from_user_url('http://google.com') is None


def test_get_tweet_urls() -> None:
    """Test get_tweet_urls()."""
    tweet = {'entities': {'urls': [{'expanded_url': 'foo'}, {'expanded_url': 'bar'}]}}
    urls = mut.get_tweet_urls(tweet)
    assert sorted(urls) == ['bar', 'foo']

    tweet = \
        {
            'entities':
                {
                    'urls': [{'expanded_url': 'url foo'}, {'expanded_url': 'url bar'}],
                },
            'retweeted_status':
                {
                    'entities':
                        {
                            'urls': [{'expanded_url': 'rt url foo'}, {'expanded_url': 'rt url bar'}],
                        }
                }
        }
    urls = mut.get_tweet_urls(tweet)
    expected_urls = ['url bar', 'url foo', 'rt url foo', 'rt url bar']
    assert sorted(urls) == sorted(expected_urls)
