"""Fetch twitter.com topic_fetch_urls from twitter api in chunks of up to 100i statuses and users."""

from typing import List, Callable
import traceback

from mediawords.db.handler import DatabaseHandler
import mediawords.tm.domains
from mediawords.util.url.twitter import parse_status_id_from_url, parse_screen_name_from_user_url
from mediawords.tm.fetch_link_utils import content_matches_topic, try_update_topic_link_ref_stories_id
from mediawords.tm.fetch_link_states import (
    FETCH_STATE_TWEET_MISSING,
    FETCH_STATE_TWEET_ADDED,
    FETCH_STATE_CONTENT_MATCH_FAILED,
    FETCH_STATE_PYTHON_ERROR,
)
from mediawords.util.twitter import fetch_100_users, get_tweet_urls, fetch_100_tweets

from mediawords.util.log import create_logger

log = create_logger(__name__)

URLS_CHUNK_SIZE = 100


class McFetchTwitterUrlsDataException(Exception):
    """default exception."""

    pass


def _log_tweet_missing(db: DatabaseHandler, topic_fetch_url: dict) -> dict:
    """Update topic_fetch_url state to tweet missing."""
    db.query(
        "update topic_fetch_urls set state = %(a)s, fetch_date = now() where topic_fetch_urls_id = %(b)s",
        {'a': FETCH_STATE_TWEET_MISSING, 'b': topic_fetch_url['topic_fetch_urls_id']})


def _log_content_match_failed(db: DatabaseHandler, topic_fetch_url: dict) -> dict:
    """Update topic_fetch_url state to content match failed."""
    db.query(
        "update topic_fetch_urls set state = %(a)s, fetch_date = now() where topic_fetch_urls_id = %(b)s",
        {'a': FETCH_STATE_CONTENT_MATCH_FAILED, 'b': topic_fetch_url['topic_fetch_urls_id']})


def _log_tweet_added(db: DatabaseHandler, topic_fetch_url: dict, story: dict) -> dict:
    """Update topic_fetch_url stat to tweet added."""
    return db.query(
        """
        update topic_fetch_urls set state=%(a)s, stories_id=%(b)s, fetch_date=now() where topic_fetch_urls_id=%(c)s
            returning *
        """,
        {'a': FETCH_STATE_TWEET_ADDED, 'b': story['stories_id'], 'c': topic_fetch_url['topic_fetch_urls_id']}).hash()


def _log_python_errpr(db: DatabaseHandler, topic_fetch_url: dict, message: str) -> dict:
    """Update topic_fetch_url stat to tweet failed."""
    return db.query(
        """
        update topic_fetch_urls set state=%(a)s, fetch_date=now(), message = %(b)s  where topic_fetch_urls_id=%(c)s
            returning *
        """,
        {'a': FETCH_STATE_PYTHON_ERROR, 'b': message, 'c': topic_fetch_url['topic_fetch_urls_id']}).hash()


def _get_undateable_tag(db: DatabaseHandler) -> dict:
    """Return the date_invalid:undateable tag."""
    tag_name = 'undateable'
    tag_set_name = 'date_invalid'

    invalid_tag = db.query(
        """
        select t.*
            from tags t
                join tag_sets ts using ( tag_sets_id )
            where
                t.tag = %(a)s and
                ts.name = %(b)s
        """,
        {'a': tag_name, 'b': tag_set_name}).hash()

    if invalid_tag is None:
        tag_set = db.find_or_create('tag_sets', {'name': tag_set_name})
        invalid_tag = db.find_or_create('tags', {'tag': tag_name, 'tag_sets_id': tag_set['tag_sets_id']})

    return invalid_tag


def _add_user_story(db: DatabaseHandler, topic: dict, user: dict, topic_fetch_urls: list) -> dict:
    """Generate a story based on the given user, as returned by the twitter api."""
    content = '%s (%s): %s' % (user['name'], user['screen_name'], user['description'])
    title = '%s (%s) | Twitter' % (user['name'], user['screen_name'])
    tweet_date = mediawords.util.sql.sql_now()
    url = 'https://twitter.com/%s' % user['screen_name']

    story = mediawords.tm.stories.generate_story(db=db, url=url, content=content, title=title, publish_date=tweet_date)
    mediawords.tm.stories.add_to_topic_stories(db=db, story=story, topic=topic, link_mined=True)

    for topic_fetch_url in topic_fetch_urls:
        topic_fetch_url = _log_tweet_added(db, topic_fetch_url, story)
        mediawords.tm.fetch_link_utils.try_update_topic_link_ref_stories_id(db, topic_fetch_url)

    # twitter user pages are undateable because there is never a consistent version of the page
    undateable_tag = _get_undateable_tag(db)
    db.query(
        "insert into stories_tags_map (stories_id, tags_id) values (%(a)s, %(b)s)",
        {'a': story['stories_id'], 'b': undateable_tag['tags_id']})

    return story


def _try_fetch_users_chunk(db: DatabaseHandler, topic: dict, topic_fetch_urls: List) -> None:
    """Fetch up to URLS_CHUNK_SIZE topic_fetch_urls from twitter api as users and add them as topic stories.

    Throw any errors up the stack.
    """
    url_lookup = {}
    for topic_fetch_url in topic_fetch_urls:
        screen_name = parse_screen_name_from_user_url(topic_fetch_url['url']).lower()
        url_lookup.setdefault(screen_name, [])
        url_lookup[screen_name].append(topic_fetch_url)

    screen_names = list(url_lookup.keys())

    log.info("fetching users for %d screen_names ..." % len(screen_names))
    users = fetch_100_users(screen_names)

    for user in users:
        try:
            screen_name = user['screen_name'].lower()
            topic_fetch_urls = url_lookup[screen_name]
            del(url_lookup[screen_name])
        except KeyError:
            raise KeyError("can't find user '%s' in urls: %s" % (user['screen_name'], str(screen_names)))

        content = "%s %s %s" % (user['name'], user['screen_name'], user['description'])
        if mediawords.tm.fetch_link_utils_utils.content_matches_topic(content, topic):
            _add_user_story(db, topic, user, topic_fetch_urls)
        else:
            [_log_content_match_failed(db, u) for u in topic_fetch_urls]

    for screen_name in url_lookup.keys():
        topic_fetch_urls = url_lookup[screen_name]
        [_log_tweet_missing(db, u) for u in topic_fetch_urls]


def _add_tweet_story(db: DatabaseHandler, topic: dict, tweet: dict, topic_fetch_urls: list) -> dict:
    """Generate a story based on the given tweet, as returned by the twitter api."""
    screen_name = tweet['user']['screen_name']
    content = tweet['text']
    title = "%s: %s" % (screen_name, content)
    tweet_date = tweet['created_at']
    url = 'https://twitter.com/%s/status/%s' % (screen_name, tweet['id'])

    story = mediawords.tm.stories.generate_story(db=db, url=url, content=content, title=title, publish_date=tweet_date)
    mediawords.tm.stories.add_to_topic_stories(db=db, story=story, topic=topic, link_mined=True)

    for topic_fetch_url in topic_fetch_urls:
        topic_fetch_url = _log_tweet_added(db, topic_fetch_url, story)
        mediawords.tm.fetch_link_utils.try_update_topic_link_ref_stories_id(db, topic_fetch_url)

    urls = get_tweet_urls(tweet)
    for url in urls:
        if mediawords.tm.domains.skip_self_linked_domain_url(db, topic['topics_id'], story['url'], url):
            log.info("skipping self linked domain url...")
            continue

        topic_link = {
            'topics_id': topic['topics_id'],
            'stories_id': story['stories_id'],
            'url': url
        }

        db.create('topic_links', topic_link)
        mediawords.tm.domains.increment_domain_links(db, topic_link)

    return story


def _try_fetch_tweets_chunk(db: DatabaseHandler, topic: dict, topic_fetch_urls: List) -> None:
    """Fetch up to URLS_CHUNK_SIZE topic_fetch_urls from twitter api as statuses and add them as topic stories.

    Throw any errors up the stack.
    """
    status_lookup = {}
    for topic_fetch_url in topic_fetch_urls:
        status_id = parse_status_id_from_url(topic_fetch_url['url'])
        status_lookup.setdefault(status_id, [])
        status_lookup[status_id].append(topic_fetch_url)

    status_ids = list(status_lookup.keys())

    log.info("fetching tweets for %d status_ids ..." % len(status_ids))
    tweets = fetch_100_tweets(status_ids)

    for tweet in tweets:
        try:
            topic_fetch_urls = status_lookup[str(tweet['id'])]
            del(status_lookup[str(tweet['id'])])
        except KeyError:
            raise KeyError("can't find tweet '%s' in ids: %s" % (tweet['id'], str(status_ids)))

        if mediawords.tm.fetch_link_utils.content_matches_topic(tweet['text'], topic):
            _add_tweet_story(db, topic, tweet, topic_fetch_urls)
        else:
            [_log_content_match_failed(db, u) for u in topic_fetch_urls]

    for status_id in status_lookup.keys():
        topic_fetch_urls = status_lookup[status_id]
        [_log_tweet_missing(db, u) for u in topic_fetch_urls]


def _call_function_on_url_chunks(db: DatabaseHandler, topic: dict, urls: List, chunk_function: Callable) -> None:
    """Call chunk_function on chunks of up to URLS_CHUNK_SIZE urls at a time.

    Catch any exceptions raised and save them in the topic_fetch_urls for the given chunk.
    """
    i = 0
    while i < len(urls):
        chunk_urls = urls[i:i + URLS_CHUNK_SIZE]

        try:
            chunk_function(db, topic, chunk_urls)
        except Exception as ex:
            log.warning("error fetching twitter data: {}".format(ex))

            topic_fetch_urls_ids = [u['topic_fetch_urls_id'] for u in urls]
            db.query(
                "update topic_fetch_urls set state = %(a)s, message = %(b)s where topic_fetch_urls_id = any(%(c)s)",
                {'a': FETCH_STATE_PYTHON_ERROR, 'b': traceback.format_exc(), 'c': topic_fetch_urls_ids})

        i += URLS_CHUNK_SIZE


def _split_urls_into_users_and_statuses(topic_fetch_urls: List) -> List:
    """Split topic_fetch_urls into status_id urls and screen_name urls."""
    status_urls = []
    user_urls = []

    for topic_fetch_url in topic_fetch_urls:
        url = topic_fetch_url['url']
        status_id = parse_status_id_from_url(url)
        if status_id:
            status_urls.append(topic_fetch_url)
        else:
            screen_name = parse_screen_name_from_user_url(url)
            if screen_name:
                user_urls.append(topic_fetch_url)
            else:
                raise McFetchTwitterUrlsDataException("url '%s' is not a twitter status or a twitter user" % url)

    return(user_urls, status_urls)


def fetch_twitter_urls(db: DatabaseHandler, topic_fetch_urls_ids: List) -> None:
    """Fetch topic_fetch_urls from twitter api as statuses and users in chunks of up to 100."""
    if len(topic_fetch_urls_ids) == 0:
        return

    topic_fetch_urls = db.query(
        "select * from topic_fetch_urls where topic_fetch_urls_id = any(%(a)s)",
        {'a': topic_fetch_urls_ids}).hashes()

    topic = db.require_by_id('topics', topic_fetch_urls[0]['topics_id'])

    (user_urls, status_urls) = _split_urls_into_users_and_statuses(topic_fetch_urls)

    _call_function_on_url_chunks(db, topic, user_urls, _try_fetch_users_chunk)
    _call_function_on_url_chunks(db, topic, status_urls, _try_fetch_tweets_chunk)
