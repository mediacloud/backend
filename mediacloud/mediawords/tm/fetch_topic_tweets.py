"""Fetch topic posts """

import csv
import datetime
import regex
import typing
from urllib.parse import urlencode

from mediawords.db import DatabaseHandler
import mediawords.tm.fetch_link
import mediawords.util.parse_json
from mediawords.util.web.user_agent import UserAgent
import mediawords.util.twitter

from mediawords.util.log import create_logger

log = create_logger(__name__)


class McFetchTopicTweetsException(Exception):
    """default exception."""

    pass


class McFetchTopicTweetsDataException(Exception):
    """exception indicating an error in the external data fetched by this module."""

    pass


class McFetchTopicTweetsConfigException(Exception):
    """exception indicating an error in the mediawords.yml configuration."""

    pass


class McFetchTopicTweetDateFetchedException(Exception):
    """exception indicating the topic tweets for the given day have already been fetched."""

    pass


def get_tweet_id_from_url(url: str) -> str:
    """Parse the tweet id from a twitter status url."""
    try:
        tweet_id = int(regex.search(r'/status/(\d+)', url).group(1))
    except AttributeError:
        raise McFetchTopicTweetsDataException("Unable to parse id from tweet url: " + url)

    return tweet_id


def fetch_meta_tweets_from_archive_org(query: str, day: str) -> list:
    """Fetch day of tweets from archive.org"""
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


def fetch_meta_tweets_from_ch(query: str, day: str) -> list:
    """Fetch day of tweets from crimson hexagon"""
    ch_monitor_id = int(query)

    ua = UserAgent()
    ua.set_max_size(100 * 1024 * 1024)
    ua.set_timeout(90)
    ua.set_timing([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])

    config = mediawords.util.config.get_config()
    if 'crimson_hexagon' not in config or 'key' not in config['crimson_hexagon']:
        raise McFetchTopicTweetsConfigException("no key in mediawords.yml at //crimson_hexagon/key.")

    key = config['crimson_hexagon']['key']

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

    data = dict(mediawords.util.parse_json.decode_json(decoded_content))

    if 'status' not in data or not data['status'] == 'success':
        raise McFetchTopicTweetsDataException("Unknown response status: " + str(data))

    meta_tweets = data['posts']

    for mt in meta_tweets:
        mt['tweet_id'] = get_tweet_id_from_url(mt['url'])

    return meta_tweets


def fetch_meta_tweets(db: DatabaseHandler, topic: dict, day: str) -> None:
    """Fetch a day of meta tweets from either CH or archive.org, depending on the topic_seed_queries row.

    The meta tweets include meta data about the tweets but not the actual tweet data, which will be subsequently
    fetched from the twitter api.  The tweet metadata can differ according to the source, but each meta_tweet
    must include a 'tweet_id' field.

    Args:
    db - db handle
    topic - topic dict
    day - '2018-09-01' format date

    Returns:
    list of dicts describing the tweets, each of which must contain a 'url' field

    """
    topic_seed_queries = db.query(
        "select * from topic_seed_queries where topics_id = %(a)s and platform = 'twitter'",
        {'a': topic['topics_id']}).hashes()

    if len(topic_seed_queries) > 1:
        raise McFetchTopicTweetsDataException("More than one topic_seed_queries for topic '%d'" % topic['topics_id'])

    if len(topic_seed_queries) < 1:
        raise McFetchTopicTweetsDataException("No topic_seed_queries for topic '%d'" % topic['topics_id'])

    topic_seed_query = topic_seed_queries[0]

    if topic_seed_query['source'] == 'crimson_hexagon':
        fmt = fetch_meta_tweets_from_ch
    elif topic_seed_query['source'] == 'archive_org':
        fmt = fetch_meta_tweets_from_archive_org
    else:
        raise McFetchTopicTweetsDataException("Unknown topic_seed_queries source '%s'" % topic_seed_query['source'])

    return fmt(topic_seed_query['query'], day)


def fetch_100_tweets(tweet_ids: list) -> list:
    """
    Fetch up to 100 tweets from the twitter api.

    Throws a McFetchTopicTweetsError if more than 100 ids are in tweet_ids.

    Arguments:
    tweet_ids - list of tweet status ids

    Return:
    list of tweet dicts as directly decoded from the json from the twitter api statuses_list api
    """
    return mediawords.util.twitter.fetch_100_tweets(tweet_ids)


def _add_tweets_to_meta_tweets(meta_tweets: list) -> None:
    """
    Given a set of meta_tweets, fetch data from twitter about each tweet and attach it under the tweet field.

    Arguments:
    meta_tweets - list of up to 100 dicts from as returned by fetch_meta_tweets()

    Return:
    None
    """
    # statuses_lookup below only works for up to 100 tweets
    assert len(meta_tweets) <= 100

    log.debug("fetching tweets for " + str(len(meta_tweets)) + " tweets")

    meta_tweet_lookup = {}
    for mt in meta_tweets:
        meta_tweet_lookup[mt['tweet_id']] = mt

    tweet_ids = list(meta_tweet_lookup.keys())

    tweets = fetch_100_tweets(tweet_ids)

    log.debug("fetched " + str(len(tweets)) + " tweets")

    for tweet in tweets:
        meta_tweet_lookup[tweet['id']]['tweet'] = tweet

    for meta_tweet in meta_tweets:
        if 'tweet' not in meta_tweet:
            log.debug("no tweet fetched for url " + meta_tweet['url'])


def _insert_tweet_urls(db: DatabaseHandler, topic_post: dict, urls: typing.List) -> typing.List:
    """Insert list of urls into topic_post_urls."""
    for url in urls:
        db.query(
            """
            insert into topic_post_urls( topic_posts_id, url )
                values( %(a)s, %(b)s )
                on conflict do nothing
            """,
            {'a': topic_post['topic_posts_id'], 'b': url})


def _remove_json_tree_nulls(d: dict):
    """Recursively traverse json tree and remove nulls from all values."""
    for k in d:
        if isinstance(d[k], dict):
            _remove_json_tree_nulls(d[k])
        elif isinstance(d[k], str):
            d[k] = d[k].replace('\x00', '')


def _store_tweet_and_urls(db: DatabaseHandler, topic_post_day: dict, meta_tweet: dict) -> None:
    """
    Store the tweet in topic_posts and its urls in topic_post_urls, using the data in meta_tweet.

    Arguments:
    db - database handler
    topic - topic dict
    topic_post_day - topic_post_day dict
    meta_tweet - meta_tweet dict

    Return:
    None
    """
    log.debug("remove nulls")
    _remove_json_tree_nulls(meta_tweet)

    log.debug("encode json")
    data_json = mediawords.util.parse_json.encode_json(meta_tweet)

    # null characters are not legal in json but for some reason get stuck in these tweets
    # data_json = data_json.replace('\x00', '')

    topic_post = {
        'topic_post_days_id': topic_post_day['topic_post_days_id'],
        'data': data_json,
        'content': meta_tweet['tweet']['text'],
        'post_id': meta_tweet['tweet_id'],
        'publish_date': meta_tweet['tweet']['created_at'],
        'author': meta_tweet['tweet']['user']['screen_name'],
        'channel': meta_tweet['tweet']['user']['screen_name']
    }

    log.debug("insert topic tweet")
    topic_post = db.query(
        """
        insert into topic_posts
            ( topic_post_days_id, data, content, post_id, publish_date, author, channel )
            values
            ( %(topic_post_days_id)s, %(data)s, %(content)s, %(post_id)s, %(publish_date)s, %(author)s, %(channel)s )
            returning *
        """,
        topic_post).hash()

    log.debug("get tweet urls")
    urls = mediawords.util.twitter.get_tweet_urls(meta_tweet['tweet'])
    log.debug("insert tweet urls")
    _insert_tweet_urls(db, topic_post, urls)

    log.debug("done")


def regenerate_tweet_urls(db: dict, topic: dict) -> None:
    """Reparse the tweet json for a given topic and try to reinsert all tweet urls."""
    topic_posts_ids = db.query(
        """
        select tt.topic_posts_id
            from topic_posts tt
                join topic_post_days ttd using ( topic_post_days_id )
            where
                topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).flat()

    for (i, topic_posts_id) in enumerate(topic_posts_ids):
        if i % 1000 == 0:
            log.info('regenerate tweet urls: %d/%d' % (i, len(topic_posts_ids)))

        topic_post = db.require_by_id('topic_posts', topic_posts_id)
        data = mediawords.util.parse_json.decode_json(topic_post['data'])
        urls = mediawords.util.twitter.get_tweet_urls(data['tweet'])
        _insert_tweet_urls(db, topic_post, urls)


def _tweet_matches_pattern(topic: dict, meta_tweet: dict) -> bool:
    """Return true if the content of the meta_tweet matches the topic pattern."""
    if 'tweet' in meta_tweet:
        return mediawords.tm.fetch_link.content_matches_topic(meta_tweet['tweet']['text'], topic)
    else:
        return False


def _fetch_tweets_for_day(
        db: DatabaseHandler,
        topic_post_day: dict,
        meta_tweets: list,
        max_tweets: typing.Optional[int] = None) -> None:
    """
    Fetch tweets for a single day.

    If posts_fetched is false for the given topic_post_days row, fetch the tweets for the given day by querying
    the list of tweets and then fetching each tweet from twitter.

    Arguments:
    db - db handle
    topic_post_day - topic_post_day dict
    meta_tweets - list of meta tweets found for day
    max_tweets - max tweets to fetch for a single day

    Return:
    None
    """
    if (max_tweets is not None):
        meta_tweets = meta_tweets[0:max_tweets]

    topics_id = topic_post_day['topics_id']
    log.info("adding %d tweets for topic %s, day %s" % (len(meta_tweets), topics_id, topic_post_day['day']))

    # we can only get 100 posts at a time from twitter
    for i in range(0, len(meta_tweets), 100):
        _add_tweets_to_meta_tweets(meta_tweets[i:i + 100])

    topic = db.require_by_id('topics', topic_post_day['topics_id'])
    meta_tweets = list(filter(lambda p: _tweet_matches_pattern(topic, p), meta_tweets))

    log.info("%d tweets remaining after match" % (len(meta_tweets)))

    db.begin()

    log.debug("inserting into topic_posts ...")

    [_store_tweet_and_urls(db, topic_post_day, meta_tweet) for meta_tweet in meta_tweets]

    topic_post_day['num_posts'] = len(meta_tweets)

    db.query(
        "update topic_post_days set posts_fetched = true, num_posts = %(a)s where topic_post_days_id = %(b)s",
        {'a': topic_post_day['num_posts'], 'b': topic_post_day['topic_post_days_id']})

    db.commit()

    log.debug("done inserting into topic_posts")


def _add_topic_post_single_day(db: DatabaseHandler, topic: dict, num_posts: int, day: datetime.datetime) -> dict:
    """
    Add a row to topic_post_day if it does not already exist.

    Arguments:
    db - database handle
    topic - topic dict
    day - date to fetch eg '2017-12-30'
    num_posts - number of tweets found for that day

    Return:
    None
    """
    # the perl-python layer was segfaulting until I added the str() around day below -hal
    topic_post_day = db.query(
        "select * from topic_post_days where topics_id = %(a)s and day = %(b)s",
        {'a': topic['topics_id'], 'b': str(day)}).hash()

    if topic_post_day is not None and topic_post_day['posts_fetched']:
        raise McFetchTopicTweetDateFetchedException("tweets already fetched for day " + str(day))

    # if we have a ttd but had not finished fetching tweets, delete it and start over
    if topic_post_day is not None:
        db.delete_by_id('topic_post_days', topic_post_day['topic_post_days_id'])

    topic_post_day = db.create(
        'topic_post_days',
        {
            'topics_id': topic['topics_id'],
            'day': day,
            'num_posts': num_posts,
            'posts_fetched': False
        })

    return topic_post_day


def _topic_post_day_fetched(db: DatabaseHandler, topic: dict, day: str) -> bool:
    """Return true if the topic_post_day exists and posts_fetched is true."""
    ttd = db.query(
        "select * from topic_post_days where topics_id = %(a)s and day = %(b)s",
        {'a': topic['topics_id'], 'b': str(day)}).hash()

    if not ttd:
        return False

    return ttd['posts_fetched'] is True


def fetch_topic_tweets(db: DatabaseHandler, topics_id: int, max_tweets_per_day: typing.Optional[int] = None) -> None:
    """For each day within the topic dates, fetch and store the tweets.

    This is the core function that fetches and stores data for twitter topics.  This function will break the
    date range for the topic into individual days and fetch tweets matching thes twitter seed query for the
    topic for each day.  This function will create a topic_post_day row for each day of tweets fetched,
    a topic_post row for each tweet fetched, and a topic_post_url row for each url found in a tweet.

    This function pulls metadata about the matching tweets from a search source (such as crimson hexagon or
    archive.org, as deteremined by the topic_seed_queries.source field) and then fetches the tweets returned
    by the search from the twitter api in batches of 100.

    Arguments:
    db - database handle
    topics_id - topic id
    max_tweets_per_day - max tweets to fetch each day

    Return:
    None
    """
    topic = db.require_by_id('topics', topics_id)

    if topic['platform'] != 'twitter':
        raise(McFetchTopicTweetsDataException("Topic platform is not 'twitter'"))

    date = datetime.datetime.strptime(topic['start_date'], '%Y-%m-%d')
    end_date = datetime.datetime.strptime(topic['end_date'], '%Y-%m-%d')
    while date <= end_date:
        try:
            log.info("fetching tweets for %s" % date)
            if not _topic_post_day_fetched(db, topic, date):
                meta_tweets = fetch_meta_tweets(db, topic, date)
                topic_post_day = _add_topic_post_single_day(db, topic, len(meta_tweets), date)
                _fetch_tweets_for_day(db, topic_post_day, meta_tweets, max_tweets_per_day)
        except McFetchTopicTweetDateFetchedException:
            pass

        date = date + datetime.timedelta(days=1)
