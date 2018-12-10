"""Routines for interacting with twitter api and data."""

import time

import tweepy

import mediawords.util.parse_json
import mediawords.util.config

from mediawords.util.log import create_logger

log = create_logger(__name__)


class McFetchTweetsException(Exception):
    """error while fetching tweets from twitter."""

    pass


def fetch_100_tweets(tweet_ids: list) -> list:
    """Implement fetch_tweets on twitter api using config data from mediawords.yml."""
    config = mediawords.util.config.get_config()

    if len(tweet_ids) > 100:
        raise McFetchTweetsException('tried to fetch more than 100 tweets')

    if 'twitter' not in config:
        raise McFetchTweetsException('missing twitter configuration in mediawords.yml')

    for field in 'consumer_key consumer_secret access_token access_token_secret'.split():
        if field not in config['twitter']:
            raise McFetchTweetsException('missing //twitter//' + field + ' value in mediawords.yml')

    auth = tweepy.OAuthHandler(config['twitter']['consumer_key'], config['twitter']['consumer_secret'])
    auth.set_access_token(config['twitter']['access_token'], config['twitter']['access_token_secret'])

    # the RawParser lets us directly decode from json to dict below
    api = tweepy.API(auth, parser=tweepy.parsers.RawParser())

    # catch all errors and do backoff retries.  don't just catch rate limit errors because we want to be
    # robust in the face of temporary network or service provider errors.
    tweets = None
    max_twitter_retries = 10
    twitter_retries = 0
    while tweets is None and twitter_retries < max_twitter_retries:
        last_exception = None
        try:
            tweets = api.statuses_lookup(tweet_ids, include_entities=True, trim_user=False)
        except tweepy.TweepError as e:
            sleep = 2 * (twitter_retries ** 2)
            log.info("twitter fetch error.  waiting " + str(sleep) + " seconds before retry ...")
            time.sleep(sleep)
            last_exception = e

        twitter_retries += 1

    if twitter_retries >= max_twitter_retries:
        raise McFetchTweetsException("unable to fetch tweets: " + str(last_exception))

    # it is hard to mock tweepy data directly, and the default tweepy objects are not json serializable,
    # so just return a direct dict decoding of the raw twitter payload
    return list(mediawords.util.parse_json.decode_json(tweets))
