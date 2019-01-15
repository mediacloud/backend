"""Routines for interacting with twitter api and data."""

import re
import typing

import tweepy

import mediawords.util.parse_json
import mediawords.util.config

from mediawords.util.log import create_logger

log = create_logger(__name__)

# configure retry behavior for tweepy
TWITTER_RETRY_DELAY = 60
TWITTER_RETRY_COUNT = 120
TWITTER_RETRY_ERRORS = set([401, 404, 500, 503])


class McFetchTweetsException(Exception):
    """error while fetching tweets from twitter."""

    pass


def get_tweepy_api() -> tweepy.API:
    """Return an authenticated tweepy api object configued for retries."""
    config = mediawords.util.config.get_config()

    # add dummy config so that testing will work
    if 'twitter' not in config:
        config['twitter'] = {
            'consumer_secret': 'UNCONFIGURED',
            'consumer_key': 'UNCONFIGURED',
            'access_token': 'UNCONFIGURED',
            'access_token_secret': 'UNCONFIGURED'
        }

    for field in 'consumer_key consumer_secret access_token access_token_secret'.split():
        if field not in config['twitter']:
            raise McFetchTweetsException('missing //twitter//' + field + ' value in mediawords.yml')

    auth = tweepy.OAuthHandler(config['twitter']['consumer_key'], config['twitter']['consumer_secret'])
    auth.set_access_token(config['twitter']['access_token'], config['twitter']['access_token_secret'])

    # the RawParser lets us directly decode from json to dict below
    api = tweepy.API(
        auth_handler=auth,
        retry_delay=TWITTER_RETRY_DELAY,
        retry_count=TWITTER_RETRY_COUNT,
        retry_errors=TWITTER_RETRY_ERRORS,
        wait_on_rate_limit=True,
        wait_on_rate_limit_notify=True,
        parser=tweepy.parsers.RawParser())

    return api


def fetch_100_users(screen_names: list) -> list:
    """Fetch data for up to 100 users."""
    if len(screen_names) > 100:
        raise McFetchTweetsException('tried to fetch more than 100 users')

    users = get_tweepy_api().lookup_users(screen_names=screen_names, include_entities=False)

    # return simple list so that this can be mocked. relies on RawParser() in get_tweepy_api
    return list(mediawords.util.parse_json.decode_json(users))


def fetch_100_tweets(tweet_ids: list) -> list:
    """Fetch data for up to 100 tweets."""
    if len(tweet_ids) > 100:
        raise McFetchTweetsException('tried to fetch more than 100 tweets')

    tweets = get_tweepy_api().statuses_lookup(tweet_ids, include_entities=True, trim_user=False)

    # return simple list so that this can be mocked. relies on RawParser() in get_tweepy_api
    return list(mediawords.util.parse_json.decode_json(tweets))


def parse_status_id_from_url(url: str) -> typing.Optional[str]:
    """Try to parse a twitter status id from a url.  Return the status id or None if not found."""
    m = re.search(r'https?://twitter.com/.*/status/(\d+)(\?.*)?$', url)
    if m:
        return m.group(1)
    else:
        return None


def parse_screen_name_from_user_url(url: str) -> typing.Optional[str]:
    """Try to parse a screen name from a twitter user page url."""
    m = re.search(r'https?://twitter.com/([^\/\?]+)(\?.*)?$', url)

    if m is None:
        return None

    user = m.group(1)
    if user in ('search', 'login'):
        return None

    return user


def get_tweet_urls(tweet: dict) -> typing.List:
    """Parse unique tweet urls from the tweet data.

    Looks for urls and media, in the tweet proper and in the retweeted_status.
    """
    urls = []
    for tweet in (tweet, tweet.get('retweeted_status', None), tweet.get('quoted_status', None)):
        if tweet is None:
            continue

        tweet_urls = [u['expanded_url'] for u in tweet['entities']['urls']]
        urls = list(set(urls) | set(tweet_urls))

    return urls
