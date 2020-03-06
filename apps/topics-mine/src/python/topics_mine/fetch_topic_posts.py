import datetime
import re
from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.parse_json import encode_json, decode_json

from topics_base.fetch_link_utils import content_matches_topic
from topics_base.twitter_url import get_tweet_urls

from topics_mine.posts import AbstractPostFetcher
from topics_mine.posts.archive_org_twitter import ArchiveOrgPostFetcher
from topics_mine.posts.crimson_hexagon_twitter import CrimsonHexagonTwitterPostFetcher
from topics_mine.posts.csv_generic import CSVStaticPostFetcher
from topics_mine.posts.pushshift_reddit import PushshiftRedditPostFetcher

log = create_logger(__name__)

# list of fields to copy from fetched posts to the topic_posts row
POST_FIELDS = ('content', 'post_id', 'author', 'channel', 'publish_date', 'url')


class McFetchTopicPostsDataException(Exception):
    """exception indicating an error in the external data fetched by this module."""
    pass


class McFetchTopicPostsConfigException(Exception):
    """exception indicating an error in the mediawords.yml configuration."""
    pass


def _insert_post_urls(db: DatabaseHandler, topic_post: dict, urls: list) -> None:
    """Insert list of urls into topic_post_urls."""
    for url in urls:
        db.query(
            """
            insert into topic_post_urls( topic_posts_id, url )
                values( %(a)s, %(b)s )
                on conflict do nothing
            """,
            {'a': topic_post['topic_posts_id'], 'b': url[0:1023]})


def _remove_json_tree_nulls(d: dict) -> None:
    """Recursively traverse json tree and remove nulls from all values."""
    for k in d:
        if isinstance(d[k], dict):
            _remove_json_tree_nulls(d[k])
        elif isinstance(d[k], str):
            d[k] = d[k].replace('\x00', '')


def _store_post_and_urls(db: DatabaseHandler, topic_post_day: dict, post: dict) -> None:
    """
    Store the tweet in topic_posts and its urls in topic_post_urls, using the data in post.

    Arguments:
    db - database handler
    topic - topic dict
    topic_post_day - topic_post_day dict
    post - post dict

    Return:
    None
    """
    log.debug("remove nulls")
    _remove_json_tree_nulls(post)

    log.debug("encode json")
    data_json = encode_json(post)

    # null characters are not legal in json but for some reason get stuck in these tweets
    # data_json = data_json.replace('\x00', '')

    topic_post = {'topic_post_days_id': topic_post_day['topic_post_days_id'], 'data': data_json}

    for field in POST_FIELDS:
        topic_post[field] = post.get(field, None)

    log.debug("insert topic post")
    topic_post = db.create('topic_posts', topic_post)

    log.debug("insert tweet urls")
    _insert_post_urls(db, topic_post, post['urls'])

    log.debug("done")


def regenerate_post_urls(db: DatabaseHandler, topic: dict) -> None:
    """Reparse the tweet json for a given topic and try to reinsert all tweet urls."""
    topic_posts_ids = db.query(
        """
        select tt.topic_posts_id
            from topic_posts tt
                join topic_post_days ttd using ( topic_post_days_id )
                join topic_seed_queries tsg using ( topic_seed_queries_id )
            where
                topics_id = %(a)s
        """,
        {'a': topic['topics_id']}).flat()

    for (i, topic_posts_id) in enumerate(topic_posts_ids):
        if i % 1000 == 0:
            log.info('regenerate tweet urls: %d/%d' % (i, len(topic_posts_ids)))

        topic_post = db.require_by_id('topic_posts', topic_posts_id)
        data = decode_json(topic_post['data'])
        urls = get_tweet_urls(data['data']['tweet'])
        _insert_post_urls(db, topic_post, urls)


def _store_posts_for_day(db: DatabaseHandler, topic_post_day: dict, posts: list) -> None:
    """
    Store posts for a single day.

    Arguments:
    db - db handle
    topic_post_day - topic_post_day dict
    posts - list of posts found for day

    Return:
    None
    """
    log.info("adding %d posts for day %s" % (len(posts), topic_post_day['day']))

    tsq = db.require_by_id('topic_seed_queries', topic_post_day['topic_seed_queries_id'])
    topic = db.require_by_id('topics', tsq['topics_id'])
    posts = list(filter(lambda p: content_matches_topic(p['content'], topic), posts))

    log.info("%d posts remaining after match" % (len(posts)))

    db.begin()

    log.debug("inserting into topic_posts ...")

    [_store_post_and_urls(db, topic_post_day, meta_tweet) for meta_tweet in posts]

    topic_post_day['num_posts'] = len(posts)

    db.query(
        "update topic_post_days set posts_fetched = true, num_posts = %(a)s where topic_post_days_id = %(b)s",
        {'a': topic_post_day['num_posts'], 'b': topic_post_day['topic_post_days_id']})

    db.commit()

    log.debug("done inserting into topic_posts")


def _add_topic_post_single_day(db: DatabaseHandler, topic_seed_query: dict, num_posts: int, day: datetime) -> dict:
    """
    Add a row to topic_post_day if it does not already exist.

    Arguments:
    db - database handle
    topic_seed_query - topic_seed_query dict
    day - date to fetch eg '2017-12-30'
    num_posts - number of posts found for that day

    Return:
    None
    """
    # the perl-python layer was segfaulting until I added the str() around day below -hal
    topic_post_day = db.query(
        "select * from topic_post_days where topic_seed_queries_id = %(a)s and day = %(b)s",
        {'a': topic_seed_query['topic_seed_queries_id'], 'b': str(day)}).hash()

    if topic_post_day is not None and topic_post_day['posts_fetched']:
        raise McFetchTopicPostsDataException("tweets already fetched for day " + str(day))

    # if we have a ttd but had not finished fetching tweets, delete it and start over
    if topic_post_day is not None:
        db.delete_by_id('topic_post_days', topic_post_day['topic_post_days_id'])

    topic_post_day = db.create(
        'topic_post_days',
        {
            'topic_seed_queries_id': topic_seed_query['topic_seed_queries_id'],
            'day': day,
            'num_posts': num_posts,
            'posts_fetched': False
        })

    return topic_post_day


def _topic_post_day_fetched(db: DatabaseHandler, topic_seed_query: dict, day: datetime) -> bool:
    """Return true if the topic_post_day exists and posts_fetched is true."""
    ttd = db.query(
        "select * from topic_post_days where topic_seed_queries_id = %(a)s and day = %(b)s",
        {'a': topic_seed_query['topic_seed_queries_id'], 'b': str(day)}).hash()

    if not ttd:
        return False

    return ttd['posts_fetched'] is True


def get_post_fetcher(topic_seed_query: dict) -> Optional[AbstractPostFetcher]:
    """get the fetch_posts function for the given topic_seed_query, or None.`"""
    source = topic_seed_query['source']
    platform = topic_seed_query['platform']

    if source == 'crimson_hexagon' and platform == 'twitter':
        fetch = CrimsonHexagonTwitterPostFetcher()
    elif source == 'archive_org' and platform == 'twitter':
        fetch = ArchiveOrgPostFetcher()
    elif source == 'csv' and platform == 'generic_post':
        fetch = CSVStaticPostFetcher()
    elif source == 'pushshift' and platform == 'reddit':
        fetch = PushshiftRedditPostFetcher()
    else:
        fetch = None

    return fetch


def fetch_posts(topic_seed_query: dict, start_date: datetime, end_date: datetime = None) -> list:
    """Fetch the posts for the given topic_seed_queries row, for the described date range."""
    if end_date is None:
        end_date = start_date + datetime.timedelta(days=1) - datetime.timedelta(seconds=1) 

    fetcher = get_post_fetcher(topic_seed_query)

    if not fetcher:
        msg = f"Unable to find fetch_posts fetcher for seed_query: {topic_seed_query}"
        raise McFetchTopicPostsDataException(msg)

    return fetcher.fetch_posts(query=topic_seed_query['query'], start_date=start_date, end_date=end_date)


def fetch_topic_posts(db: DatabaseHandler, topic_seed_query: dict) -> None:
    """For each day within the topic dates, fetch and store posts returned by the topic_seed_query.

    This is the core function that fetches and stores data for sharing topics.  This function will break the
    date range for the topic into individual days and fetch posts matching the topic_seed_query for the
    for each day.  This function will create a topic_post_day row for each day of posts fetched,
    a topic_post row for each post fetched, and a topic_post_url row for each url found in a post.

    Arguments:
    db - database handle
    topics_id - topic id

    Return:
    None
    """
    topic = db.require_by_id('topics', topic_seed_query['topics_id'])

    date = datetime.datetime.strptime(topic['start_date'], '%Y-%m-%d')

    end_date = datetime.datetime.strptime(topic['end_date'], '%Y-%m-%d')
    while date <= end_date:
        log.debug("fetching posts for %s" % date)
        if not _topic_post_day_fetched(db, topic_seed_query, date):
            posts = fetch_posts(topic_seed_query, date)
            topic_post_day = _add_topic_post_single_day(db, topic_seed_query, len(posts), date)
            _store_posts_for_day(db, topic_post_day, posts)

        date = date + datetime.timedelta(days=1)
