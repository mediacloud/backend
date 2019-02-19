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
TWITTER_RETRY_COUNT = 45
TWITTER_RETRY_ERRORS = set([401, 404, 500, 503])


class McFetchTweetsException(Exception):
    """error while fetching tweets from twitter."""

    pass


def get_tweepy_api() -> tweepy.API:
    """Return an authenticated tweepy api object configued for retries."""
    config = mediawords.util.config.get_config()

    # add dummy config so that testing will work
    if 'twitter' in config:
        twitter_config = config['twitter']
    else:
        twitter_config = {
            'consumer_secret': 'UNCONFIGURED',
            'consumer_key': 'UNCONFIGURED',
            'access_token': 'UNCONFIGURED',
            'access_token_secret': 'UNCONFIGURED'
        }

    for field in 'consumer_key consumer_secret access_token access_token_secret'.split():
        if field not in twitter_config:
            raise McFetchTweetsException('missing //twitter//' + field + ' value in mediawords.yml')

    auth = tweepy.OAuthHandler(twitter_config['consumer_key'], twitter_config['consumer_secret'])
    auth.set_access_token(twitter_config['access_token'], twitter_config['access_token_secret'])

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

    # tweepy returns a 404 if none of the screen names exist, and that 404 is indistiguishable from a 404
    # indicating that tweepy can't connect to the twitter api.  in the latter case, we want to let tweepy use its
    # retry mechanism, but not the former.  so we add a dummy account that we know exists to every request
    # to make sure any 404 we get back is an actual 404.
    dummy_account = 'cyberhalroberts'
    dummy_account_appended = False

    if 'cyberhalroberts' not in screen_names:
        screen_names.append('cyberhalroberts')
        dummy_account_appended = True

    users_json = get_tweepy_api().lookup_users(screen_names=screen_names, include_entities=False)

    users = list(mediawords.util.parse_json.decode_json(users_json))

    # if we added the dummy account, remove it from the results
    if dummy_account_appended:
        users = list(filter(lambda u: u['screen_name'] != dummy_account, users))

    # return simple list so that this can be mocked. relies on RawParser() in get_tweepy_api
    return users


def _fetch_and_attach_retweets(tweets: list) -> list:
    """Fetch retweets and attach them to the retweeted_status fields of the given tweets."""
    log.warning('fetching retweets ...')
    retweeted_ids = []
    tweet_lookup = {}
    for tweet in tweets:
        if 'retweeted_status' in tweet:
            log.warning('fetch retweet ' + str(tweet['retweeted_status']['id_str']))
            retweeted_ids.append(tweet['retweeted_status']['id_str'])
            tweet_lookup[tweet['retweeted_status']['id_str']] = tweet

    retweets = fetch_100_tweets(tweet_ids=retweeted_ids, fetch_retweets=False)

    for retweet in retweets:
        log.warning('attach expanded retweet ' + str(retweet['id_str']))
        if retweet['id_str'] in tweet_lookup:
            tweet = tweet_lookup[retweet['id_str']]
            tweet['expanded_retweeted_status'] = retweet
        else:
            log.warning('Unable to find tweet for retweet: %s' % retweet['id_str'])

    return tweets


def fetch_100_tweets(tweet_ids: list, fetch_retweets: bool = True) -> list:
    """Fetch data for up to 100 tweets."""
    if len(tweet_ids) > 100:
        raise McFetchTweetsException('tried to fetch more than 100 tweets')

    log.warning("fetching tweets: %s" % tweet_ids)

    tweets = get_tweepy_api().statuses_lookup(tweet_ids, include_entities=True, trim_user=False)

    # return simple list so that this can be mocked. relies on RawParser() in get_tweepy_api
    tweets = list(mediawords.util.parse_json.decode_json(tweets))

    if fetch_retweets:
        _fetch_and_attach_retweets(tweets)

    return tweets


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
