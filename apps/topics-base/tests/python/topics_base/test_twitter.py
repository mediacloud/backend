"""Unit tests for mediawords.util.twitter."""

from urllib.parse import urlparse, parse_qs

import requests
import requests_mock

from mediawords.util.parse_json import encode_json

from topics_base.twitter import fetch_100_users, fetch_100_tweets

MIN_TEST_TWEET_LENGTH = 10
MIN_TEST_TWITTER_USER_LENGTH = 3


def _mock_users_lookup(request: requests.PreparedRequest, context) -> str:
    """Mock twitter /statuses/lookup response."""
    params = parse_qs(request.body)

    screen_names = params['screen_name'][0].split(',')

    users = []
    for i, screen_name in enumerate(screen_names):
        user = {
            'id': str(i),
            'name': 'user %d' % i,
            'screen_name': screen_name,
            'description': "test description for user %d" % i}
        users.append(user)

    context.status_code = 200
    context.headers = {'Content-Type': 'application/json; charset=UTF-8'}
    return encode_json(users)


def test_fetch_100_users() -> None:
    """Test fetch_100_tweets using mock."""

    with requests_mock.Mocker() as m:
        m.post("https://api.twitter.com/1.1/users/lookup.json", text=_mock_users_lookup)
        got_users = fetch_100_users(['foo', 'bar', 'bat'])

    got_screen_names = [u['screen_name'] for u in got_users]

    assert sorted(got_screen_names) == ['bar', 'bat', 'foo']


def _mock_statuses_lookup(request: requests.PreparedRequest, context) -> str:
    """Mock twitter /statuses/lookup response."""
    params = parse_qs(urlparse(request.url).query)

    ids = params['id'][0].split(',')

    json = ','.join(['{"id": %s, "text": "content %s"}' % (tweet_id, tweet_id) for tweet_id in ids])

    json = '[%s]' % json

    context.status_code = 200
    context.headers = {'Content-Type': 'application/json; charset=UTF-8'}
    return json


def test_fetch_100_tweets() -> None:
    """Test fetch_100_tweets using mock."""

    with requests_mock.Mocker() as m:
        m.get("https://api.twitter.com/1.1/statuses/lookup.json", text=_mock_statuses_lookup)
        got_tweets = fetch_100_tweets([1, 2, 3, 4])

    assert sorted(got_tweets, key=lambda t: t['id']) == [
        {'id': 1, 'text': "content 1"},
        {'id': 2, 'text': "content 2"},
        {'id': 3, 'text': "content 3"},
        {'id': 4, 'text': "content 4"}]
