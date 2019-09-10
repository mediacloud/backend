"""Use the Crimson Hexagon API to lookup tweets relevant to a topic, then fetch each of those tweets from twitter."""

import abc
import csv
import datetime
import re
from typing import Optional, List
from urllib.parse import urlencode

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.parse_json import decode_json, encode_json
from mediawords.util.web.user_agent import UserAgent

from topics_base.fetch_link_utils import content_matches_topic
from topics_base.twitter import fetch_100_tweets as fetch_100_tweets_impl
from topics_base.twitter_url import get_tweet_urls

from topics_mine.config import TopicsMineConfig

log = create_logger(__name__)


class McFetchTopicTweetsException(Exception):
    """default exception."""
    pass


class McFetchTopicTweetsDataException(Exception):
    """exception indicating an error in the external data fetched by this module."""
    pass


class McFetchTopicTweetsConfigException(Exception):
    """exception indicating an error in the configuration."""
    pass


class McFetchTopicTweetDateFetchedException(Exception):
    """exception indicating the topic tweets for the given day have already been fetched."""
    pass


def get_tweet_id_from_url(url: str) -> int:
    """Parse the tweet id from a twitter status url."""
    try:
        tweet_id = int(re.search(r'/status/(\d+)', url).group(1))
    except AttributeError:
        raise McFetchTopicTweetsDataException("Unable to parse id from tweet url: " + url)

    return tweet_id


class AbstractTweetFetcher(object, metaclass=abc.ABCMeta):
    """Abstract class for fetching tweets."""

    # Encapsulated into an abstract class so that tests could replace those methods with their own mock alternatives
    # without having to monkey-patch the class itself

    @staticmethod
    @abc.abstractmethod
    def fetch_meta_tweets_from_ch(query: str, day: datetime.datetime) -> list:
        """Fetch day of tweets from crimson hexagon."""
        raise NotImplemented("Abstract method.")

    @staticmethod
    @abc.abstractmethod
    def fetch_meta_tweets_from_archive_org(query: str, day: datetime.datetime) -> list:
        """Fetch day of tweets from archive.org"""
        raise NotImplemented("Abstract method.")

    @staticmethod
    @abc.abstractmethod
    def fetch_100_tweets(tweet_ids: list) -> list:
        """Fetch data for up to 100 tweets."""
        raise NotImplemented("Abstract method.")


class DefaultTweetFetcher(AbstractTweetFetcher):
    """Default tweet fetcher."""

    @staticmethod
    def fetch_meta_tweets_from_ch(query: str, day: datetime.datetime) -> list:
        ch_monitor_id = int(query)

        ua = UserAgent()
        ua.set_max_size(100 * 1024 * 1024)
        ua.set_timeout(90)
        ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

        tm_config = TopicsMineConfig()
        key = tm_config.crimson_hexagon_api_key()

        if not key:
            raise McFetchTopicTweetsConfigException("Crimson Hexagon API key is not set.")

        next_day = day + datetime.timedelta(days=1)

        day_arg = day.strftime('%Y-%m-%d')
        next_day_arg = next_day.strftime('%Y-%m-%d')

        url = ("https://api.crimsonhexagon.com/api/monitor/posts?auth=%s&id=%d&start=%s&end=%s&extendLimit=true" %
               (key, ch_monitor_id, day_arg, next_day_arg))

        log.debug("crimson hexagon url: " + url)

        response = ua.get(url)

        if not response.is_success():
            raise McFetchTopicTweetsDataException("error fetching posts: " + response.decoded_content())

        decoded_content = response.decoded_content()

        data = dict(decode_json(decoded_content))

        if 'status' not in data or not data['status'] == 'success':
            raise McFetchTopicTweetsDataException("Unknown response status: " + str(data))

        meta_tweets = data['posts']

        for mt in meta_tweets:
            mt['tweet_id'] = get_tweet_id_from_url(mt['url'])

        return meta_tweets

    @staticmethod
    def fetch_meta_tweets_from_archive_org(query: str, day: datetime.datetime) -> list:
        ua = UserAgent()
        ua.set_max_size(100 * 1024 * 1024)
        ua.set_timeout(90)
        ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

        next_day = day + datetime.timedelta(days=1)

        day_arg = day.strftime('%Y-%m-%d')
        next_day_arg = next_day.strftime('%Y-%m-%d')

        enc_query = urlencode({'q': query, 'date_from': day_arg, 'date_to': next_day_arg})

        url = "https://searchtweets.archivelab.org/export?" + enc_query

        log.debug("archive.org url: " + url)

        response = ua.get(url)

        if not response.is_success():
            raise McFetchTopicTweetsDataException("error fetching posts: " + response.decoded_content())

        decoded_content = response.decoded_content()

        # sometimes we get null characters, which choke the csv module
        decoded_content = decoded_content.replace('\x00', '')

        meta_tweets = []
        lines = decoded_content.splitlines()[1:]
        for row in csv.reader(lines, delimiter="\t"):
            fields = 'user_name user_screen_name lang text timestamp_ms url'.split(' ')
            meta_tweet = {}
            for i, field in enumerate(fields):
                meta_tweet[field] = row[i] if i < len(row) else ''

            if 'url' not in meta_tweet or meta_tweet['url'] == '':
                log.warning("meta_tweet '%s' does not have a url" % str(row))
                continue

            meta_tweet['tweet_id'] = get_tweet_id_from_url(meta_tweet['url'])

            meta_tweets.append(meta_tweet)

        return meta_tweets

    @staticmethod
    def fetch_100_tweets(tweet_ids: list) -> list:
        return fetch_100_tweets_impl(tweet_ids)


def fetch_meta_tweets(db: DatabaseHandler,
                      topic: dict,
                      day: datetime.datetime,
                      tweet_fetcher: Optional[AbstractTweetFetcher] = None) -> list:
    """
    Fetch a day of meta tweets from either CH or archive.org, depending on the topic_seed_queries row.

    The meta tweets include meta data about the tweets but not the actual tweet data, which will be subsequently
    fetched from the twitter api.  The tweet metadata can differ according to the source, but each meta_tweet
    must include a 'tweet_id' field.

    :param db: database handler
    :param topic: topic dictionary
    :param day: YYYY-mm-dd day, e.g. "2018-09-01"
    :param tweet_fetcher: optional tweet fetcher instance; useful for mocking the tweet fetching for testing purposes
    :return: list of dicts describing the tweets, each of which must contain a 'url' field
    """

    if not tweet_fetcher:
        tweet_fetcher = DefaultTweetFetcher()

    topic_seed_queries = db.query(
        "select * from topic_seed_queries where topics_id = %(a)s and platform = 'twitter'",
        {'a': topic['topics_id']}).hashes()

    if len(topic_seed_queries) > 1:
        raise McFetchTopicTweetsDataException("More than one topic_seed_queries for topic '%d'" % topic['topics_id'])

    if len(topic_seed_queries) < 1:
        raise McFetchTopicTweetsDataException("No topic_seed_queries for topic '%d'" % topic['topics_id'])

    topic_seed_query = topic_seed_queries[0]

    if topic_seed_query['source'] == 'crimson_hexagon':
        fmt = tweet_fetcher.fetch_meta_tweets_from_ch
    elif topic_seed_query['source'] == 'archive_org':
        fmt = tweet_fetcher.fetch_meta_tweets_from_archive_org
    else:
        raise McFetchTopicTweetsDataException("Unknown topic_seed_queries source '%s'" % topic_seed_query['source'])

    return fmt(topic_seed_query['query'], day)


def _add_tweets_to_meta_tweets(meta_tweets: list, tweet_fetcher: AbstractTweetFetcher) -> None:
    """
    Given a set of meta_tweets, fetch data from twitter about each tweet and attach it under the tweet field.

    :param meta_tweets: list of up to 100 dicts from as returned by fetch_meta_tweets()
    :param tweet_fetcher: optional tweet fetcher instance; useful for mocking the tweet fetching for testing purposes
    :return: FIXME
    """
    # statuses_lookup below only works for up to 100 tweets
    assert len(meta_tweets) <= 100

    log.debug("fetching tweets for " + str(len(meta_tweets)) + " tweets")

    meta_tweet_lookup = {}
    for mt in meta_tweets:
        meta_tweet_lookup[mt['tweet_id']] = mt

    tweet_ids = list(meta_tweet_lookup.keys())

    tweets = tweet_fetcher.fetch_100_tweets(tweet_ids)

    log.debug("fetched " + str(len(tweets)) + " tweets")

    for tweet in tweets:
        meta_tweet_lookup[tweet['id']]['tweet'] = tweet

    for meta_tweet in meta_tweets:
        if 'tweet' not in meta_tweet:
            log.debug("no tweet fetched for url " + meta_tweet['url'])


def _insert_tweet_urls(db: DatabaseHandler, topic_tweet: dict, urls: List) -> None:
    """Insert list of urls into topic_tweet_urls."""
    for url in urls:
        db.query(
            """
            insert into topic_tweet_urls( topic_tweets_id, url )
                values( %(a)s, %(b)s )
                on conflict do nothing
            """,
            {'a': topic_tweet['topic_tweets_id'], 'b': url})


def _remove_json_tree_nulls(d: dict):
    """Recursively traverse json tree and remove nulls from all values."""
    for k in d:
        if isinstance(d[k], dict):
            _remove_json_tree_nulls(d[k])
        elif isinstance(d[k], str):
            d[k] = d[k].replace('\x00', '')


def _store_tweet_and_urls(db: DatabaseHandler, topic_tweet_day: dict, meta_tweet: dict) -> None:
    """
    Store the tweet in topic_tweets and its urls in topic_tweet_urls, using the data in meta_tweet.

    :param db: database handler
    :param topic_tweet_day: topic_tweet_day dictionary
    :param meta_tweet: meta_tweet dictionary
    :return:
    """
    log.debug("remove nulls")
    _remove_json_tree_nulls(meta_tweet)

    log.debug("encode json")
    data_json = encode_json(meta_tweet)

    # null characters are not legal in json but for some reason get stuck in these tweets
    # data_json = data_json.replace('\x00', '')

    topic_tweet = {
        'topic_tweet_days_id': topic_tweet_day['topic_tweet_days_id'],
        'data': data_json,
        'content': meta_tweet['tweet']['text'],
        'tweet_id': meta_tweet['tweet_id'],
        'publish_date': meta_tweet['tweet']['created_at'],
        'twitter_user': meta_tweet['tweet']['user']['screen_name']
    }

    log.debug("insert topic tweet")
    topic_tweet = db.query(
        """
        insert into topic_tweets
            ( topic_tweet_days_id, data, content, tweet_id, publish_date, twitter_user )
            values
            ( %(topic_tweet_days_id)s, %(data)s, %(content)s, %(tweet_id)s, %(publish_date)s, %(twitter_user)s )
            returning *
        """,
        topic_tweet).hash()

    log.debug("get tweet urls")
    urls = get_tweet_urls(meta_tweet['tweet'])
    log.debug("insert tweet urls")
    _insert_tweet_urls(db, topic_tweet, urls)

    log.debug("done")


def regenerate_tweet_urls(db: DatabaseHandler, topic: dict) -> None:
    """Reparse the tweet json for a given topic and try to reinsert all tweet urls."""
    topic_tweets_ids = db.query(
        """
        select tt.topic_tweets_id
            from topic_tweets tt
                join topic_tweet_days ttd using ( topic_tweet_days_id )
            where
                topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).flat()

    for (i, topic_tweets_id) in enumerate(topic_tweets_ids):
        if i % 1000 == 0:
            log.info('regenerate tweet urls: %d/%d' % (i, len(topic_tweets_ids)))

        topic_tweet = db.require_by_id('topic_tweets', topic_tweets_id)
        data = decode_json(topic_tweet['data'])
        urls = get_tweet_urls(data['tweet'])
        _insert_tweet_urls(db, topic_tweet, urls)


def _tweet_matches_pattern(topic: dict, meta_tweet: dict) -> bool:
    """Return true if the content of the meta_tweet matches the topic pattern."""
    if 'tweet' in meta_tweet:
        return content_matches_topic(meta_tweet['tweet']['text'], topic)
    else:
        return False


def _fetch_tweets_for_day(
        db: DatabaseHandler,
        topic_tweet_day: dict,
        meta_tweets: list,
        tweet_fetcher: AbstractTweetFetcher,
        max_tweets: Optional[int] = None) -> None:
    """
    Fetch tweets for a single day.

    If tweets_fetched is false for the given topic_tweet_days row, fetch the tweets for the given day by querying
    the list of tweets and then fetching each tweet from twitter.

    :param db: database handler
    :param topic_tweet_day: topic_tweet_day dictionary
    :param meta_tweets: list of meta tweets found for the day
    :param tweet_fetcher: optional tweet fetcher instance; useful for mocking the tweet fetching for testing purposes
    :param max_tweets: max. tweets to fetch for a single day
    :return: FIXME
    """
    if max_tweets is not None:
        meta_tweets = meta_tweets[0:max_tweets]

    topics_id = topic_tweet_day['topics_id']
    log.info("adding %d tweets for topic %s, day %s" % (len(meta_tweets), topics_id, topic_tweet_day['day']))

    # we can only get 100 posts at a time from twitter
    for i in range(0, len(meta_tweets), 100):
        _add_tweets_to_meta_tweets(meta_tweets=meta_tweets[i:i + 100], tweet_fetcher=tweet_fetcher)

    topic = db.require_by_id('topics', topic_tweet_day['topics_id'])
    meta_tweets = list(filter(lambda p: _tweet_matches_pattern(topic, p), meta_tweets))

    log.info("%d tweets remaining after match" % (len(meta_tweets)))

    db.begin()

    log.debug("inserting into topic_tweets ...")

    [_store_tweet_and_urls(db, topic_tweet_day, meta_tweet) for meta_tweet in meta_tweets]

    topic_tweet_day['num_tweets'] = len(meta_tweets)

    db.query(
        "update topic_tweet_days set tweets_fetched = true, num_tweets = %(a)s where topic_tweet_days_id = %(b)s",
        {'a': topic_tweet_day['num_tweets'], 'b': topic_tweet_day['topic_tweet_days_id']})

    db.commit()

    log.debug("done inserting into topic_tweets")


def _add_topic_tweet_single_day(db: DatabaseHandler, topic: dict, num_tweets: int, day: datetime.datetime) -> dict:
    """
    Add a row to topic_tweet_day if it does not already exist.

    :param db: database handle
    :param topic: topic
    :param num_tweets: number of tweets found for that day
    :param day: date to fetch, e.g. "2017-12-30"
    :return: FIXME
    """
    # the perl-python layer was segfaulting until I added the str() around day below -hal
    topic_tweet_day = db.query(
        "select * from topic_tweet_days where topics_id = %(a)s and day = %(b)s",
        {'a': topic['topics_id'], 'b': str(day)}).hash()

    if topic_tweet_day is not None and topic_tweet_day['tweets_fetched']:
        raise McFetchTopicTweetDateFetchedException("tweets already fetched for day " + str(day))

    # if we have a ttd but had not finished fetching tweets, delete it and start over
    if topic_tweet_day is not None:
        db.delete_by_id('topic_tweet_days', topic_tweet_day['topic_tweet_days_id'])

    topic_tweet_day = db.create(
        'topic_tweet_days',
        {
            'topics_id': topic['topics_id'],
            'day': day,
            'num_tweets': num_tweets,
            'tweets_fetched': False
        })

    return topic_tweet_day


def _topic_tweet_day_fetched(db: DatabaseHandler, topic: dict, day: str) -> bool:
    """Return true if the topic_tweet_day exists and tweets_fetched is true."""
    ttd = db.query(
        "select * from topic_tweet_days where topics_id = %(a)s and day = %(b)s",
        {'a': topic['topics_id'], 'b': str(day)}).hash()

    if not ttd:
        return False

    return ttd['tweets_fetched'] is True


def fetch_topic_tweets(db: DatabaseHandler,
                       topics_id: int,
                       max_tweets_per_day: Optional[int] = None,
                       tweet_fetcher: Optional[AbstractTweetFetcher] = None) -> None:
    """
    For each day within the topic dates, fetch and store the tweets.

    This is the core function that fetches and stores data for twitter topics.  This function will break the
    date range for the topic into individual days and fetch tweets matching the twitter seed query for the
    topic for each day.  This function will create a topic_tweet_day row for each day of tweets fetched,
    a topic_tweet row for each tweet fetched, and a topic_tweet_url row for each url found in a tweet.

    This function pulls metadata about the matching tweets from a search source (such as crimson hexagon or
    archive.org, as determined by the topic_seed_queries.source field) and then fetches the tweets returned
    by the search from the twitter api in batches of 100.

    :param db: database handler
    :param topics_id: topic ID
    :param max_tweets_per_day: max. tweets to fetch each day
    :param tweet_fetcher: optional tweet fetcher instance; useful for mocking the tweet fetching for testing purposes
    """

    if not tweet_fetcher:
        tweet_fetcher = DefaultTweetFetcher()

    topic = db.require_by_id('topics', topics_id)

    if topic['platform'] != 'twitter':
        raise McFetchTopicTweetsDataException("Topic platform is not 'twitter'")

    date = datetime.datetime.strptime(topic['start_date'], '%Y-%m-%d')
    end_date = datetime.datetime.strptime(topic['end_date'], '%Y-%m-%d')
    while date <= end_date:
        try:
            log.info("fetching tweets for %s" % date)
            if not _topic_tweet_day_fetched(db, topic, date):
                meta_tweets = fetch_meta_tweets(db=db, topic=topic, day=date, tweet_fetcher=tweet_fetcher)
                topic_tweet_day = _add_topic_tweet_single_day(db, topic, len(meta_tweets), date)

                _fetch_tweets_for_day(
                    db=db,
                    topic_tweet_day=topic_tweet_day,
                    meta_tweets=meta_tweets,
                    max_tweets=max_tweets_per_day,
                    tweet_fetcher=tweet_fetcher,
                )

        except McFetchTopicTweetDateFetchedException:
            pass

        date = date + datetime.timedelta(days=1)
