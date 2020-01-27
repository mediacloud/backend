"""Routines for interacting with twitter api and data."""

import tweepy
from tweepy.parsers import RawParser
from urllib.parse import urlparse, parse_qs

from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.log import create_logger
from topics_base.config import TopicsBaseConfig

log = create_logger(__name__)

# configure retry behavior for tweepy
TWITTER_RETRY_DELAY = 60
TWITTER_RETRY_COUNT = 45
TWITTER_RETRY_ERRORS = {401, 404, 500, 503}


class McFetchTweetsException(Exception):
    """error while fetching tweets from twitter."""
    pass


def _get_tweepy_api() -> tweepy.API:
    """Return an authenticated tweepy api object configured for retries."""

    config = TopicsBaseConfig()
    twitter_config = config.twitter_api()

    auth = tweepy.OAuthHandler(twitter_config.consumer_key(), twitter_config.consumer_secret())
    auth.set_access_token(twitter_config.access_token(), twitter_config.access_token_secret())

    # the RawParser lets us directly decode from json to dict below
    api = tweepy.API(
        auth_handler=auth,
        retry_delay=TWITTER_RETRY_DELAY,
        retry_count=TWITTER_RETRY_COUNT,
        retry_errors=TWITTER_RETRY_ERRORS,
        wait_on_rate_limit=True,
        wait_on_rate_limit_notify=True,
        parser=RawParser())

    return api


def fetch_100_users(screen_names: list) -> list:
    """Fetch data for up to 100 users."""
    if len(screen_names) > 100:
        raise McFetchTweetsException('tried to fetch more than 100 users')

    # tweepy returns a 404 if none of the screen names exist, and that 404 is indistinguishable from a 404
    # indicating that tweepy can't connect to the twitter api.  in the latter case, we want to let tweepy use its
    # retry mechanism, but not the former.  so we add a dummy account that we know exists to every request
    # to make sure any 404 we get back is an actual 404.
    dummy_account = 'cyberhalroberts'
    dummy_account_appended = False

    if 'cyberhalroberts' not in screen_names:
        screen_names.append('cyberhalroberts')
        dummy_account_appended = True

    users_json = _get_tweepy_api().lookup_users(screen_names=screen_names, include_entities=False)

    users = list(decode_json(users_json))

    # if we added the dummy account, remove it from the results
    if dummy_account_appended:
        users = list(filter(lambda u: u['screen_name'] != dummy_account, users))

    # return simple list so that this can be mocked. relies on RawParser() in _get_tweepy_api()
    return users


def fetch_100_tweets(tweet_ids: list) -> list:
    """Fetch data for up to 100 tweets."""
    if len(tweet_ids) > 100:
        raise McFetchTweetsException('tried to fetch more than 100 tweets')

    if len(tweet_ids) == 0:
        return []

    tweets = _get_tweepy_api().statuses_lookup(tweet_ids, include_entities=True, trim_user=False, tweet_mode='extended')

    # return simple list so that this can be mocked. relies on RawParser() in _get_tweepy_api()
    tweets = list(decode_json(tweets))

    for tweet in tweets:
        if 'full_text' in tweet:
            tweet['text'] = tweet['full_text']

    return tweets


def _mock_users(request, context) -> str:
    """Mock twitter /statuses/lookup response for requests_mock."""
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


def _mock_statuses(request, context) -> str:
    """Mock twitter /statuses/lookup response for requests_mock."""
    params = parse_qs(urlparse(request.url).query)

    ids = params['id'][0].split(',')

    tweets = []
    for tweet_id in ids:
        tweet = {
            'id': int(tweet_id),
            'id_str': str(tweet_id),
            'text': 'content %s' % tweet_id,
            'user': {'screen_name': 'user_%s' % tweet_id},
            'created_at': 'Thu Apr 06 15:24:15 +0000 2019',
            'place': {},
            'entitites': {}}

        tweets.append(tweet)

    json = encode_json(tweets)

    context.status_code = 200
    context.headers = {'Content-Type': 'application/json; charset=UTF-8'}

    return json


def add_mockers(m) -> None:
    """Setup request_mock adapter to mock twitter status and user api requests."""
    m.post("https://api.twitter.com/1.1/users/lookup.json", text=_mock_users)
    m.get("https://api.twitter.com/1.1/statuses/lookup.json", text=_mock_statuses)
