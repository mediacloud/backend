import re

from mediawords.util.log import create_logger

from topics_base.twitter import fetch_100_tweets

log = create_logger(__name__)


def add_tweets_to_meta_tweets(meta_tweets: list) -> None:
    """
    Given a set of meta_tweets, fetch data from twitter about each tweet and attach it under the tweet field.

    Arguments:
    meta_tweets - list of dicts, each of which must have a 'tweet_id'

    Return:
    None
    """
    log.debug("fetching tweets for " + str(len(meta_tweets)) + " tweets")

    for i in range(0, len(meta_tweets), 100):
        fetch_tweets = meta_tweets[i:i + 100]

        fetch_tweet_lookup = {}
        for ft in fetch_tweets:
            fetch_tweet_lookup[ft['tweet_id']] = ft

        tweet_ids = list(fetch_tweet_lookup.keys())

        tweets = fetch_100_tweets(tweet_ids)

        log.debug("fetched " + str(len(tweets)) + " tweets")

        for tweet in tweets:
            fetch_tweet_lookup[tweet['id']]['tweet'] = tweet

        for fetch_tweet in fetch_tweets:
            if 'tweet' not in fetch_tweet:
                log.debug("no tweet fetched for url " + fetch_tweet['url'])


def get_tweet_id_from_url(url: str) -> int:
    """Parse the tweet id from a twitter status url."""
    try:
        tweet_id = int(re.search(r'/status/(\d+)', url).group(1))
    except AttributeError:
        raise ValueError("Unable to parse id from tweet url: " + url)

    return tweet_id
