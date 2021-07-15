"""Fetch twitter.com topic_fetch_urls from twitter api in chunks of up to 100i statuses and users."""

from typing import List, Callable, Dict, Any
import traceback

from mediawords.db.handler import DatabaseHandler
from mediawords.util.sql import sql_now
from mediawords.util.log import create_logger
from topics_base.twitter_url import parse_status_id_from_url, parse_screen_name_from_user_url
from topics_base.fetch_link_utils import content_matches_topic, try_update_topic_link_ref_stories_id
from topics_base.fetch_states import (
    FETCH_STATE_TWEET_MISSING,
    FETCH_STATE_TWEET_ADDED,
    FETCH_STATE_CONTENT_MATCH_FAILED,
    FETCH_STATE_PYTHON_ERROR,
)
from topics_base.domains import skip_self_linked_domain_url, increment_domain_links
from topics_base.stories import generate_story, add_to_topic_stories
from topics_base.twitter import fetch_100_users, fetch_100_tweets
from topics_base.twitter_url import get_tweet_urls

log = create_logger(__name__)

URLS_CHUNK_SIZE = 100


class McFetchTwitterUrlsDataException(Exception):
    """Default exception."""
    pass


def _log_tweet_missing(db: DatabaseHandler, topic_fetch_url: dict) -> None:
    """Update topic_fetch_url state to tweet missing."""
    db.query("""
        UPDATE topic_fetch_urls SET
            state = %(state)s,
            fetch_date = NOW()
        WHERE
            topics_id = %(topics_id)s AND
            topic_fetch_urls_id = %(topic_fetch_urls_id)s
    """, {
        'state': FETCH_STATE_TWEET_MISSING,
        'topics_id': topic_fetch_url['topics_id'],
        'topic_fetch_urls_id': topic_fetch_url['topic_fetch_urls_id'],
    })


def _log_content_match_failed(db: DatabaseHandler, topic_fetch_url: dict) -> None:
    """Update topic_fetch_url state to content match failed."""
    db.query("""
        UPDATE topic_fetch_urls SET
            state = %(state)s,
            fetch_date = NOW()
        WHERE
            topics_id = %(topics_id)s AND
            topic_fetch_urls_id = %(topic_fetch_urls_id)s
    """, {
        'state': FETCH_STATE_CONTENT_MATCH_FAILED,
        'topics_id': topic_fetch_url['topics_id'],
        'topic_fetch_urls_id': topic_fetch_url['topic_fetch_urls_id'],
    })


def _log_tweet_added(db: DatabaseHandler, topic_fetch_url: dict, story: dict) -> dict:
    """Update topic_fetch_url stat to tweet added."""
    return db.query("""
        UPDATE topic_fetch_urls
        SET state = %(state)s,
            stories_id = %(stories_id)s,
            fetch_date = NOW()
        WHERE
            topics_id = %(topics_id)s AND
            topic_fetch_urls_id = %(topic_fetch_urls_id)s
        RETURNING *
    """, {
        'state': FETCH_STATE_TWEET_ADDED,
        'stories_id': story['stories_id'],
        'topics_id': topic_fetch_url['topics_id'],
        'topic_fetch_urls_id': topic_fetch_url['topic_fetch_urls_id'],
    }).hash()


def _get_undateable_tag(db: DatabaseHandler) -> dict:
    """Return the date_invalid:undateable tag."""
    tag_name = 'undateable'
    tag_set_name = 'date_invalid'

    invalid_tag = db.query("""
        SELECT t.*
        FROM tags AS t
            INNER JOIN tag_sets AS ts USING (tag_sets_id)
        WHERE
            t.tag = %(tag_name)s AND
            ts.name = %(tag_set_name)s
    """, {
        'tag_name': tag_name,
        'tag_set_name': tag_set_name,
    }).hash()

    if invalid_tag is None:
        tag_set = db.find_or_create('tag_sets', {'name': tag_set_name})
        invalid_tag = db.find_or_create('tags', {'tag': tag_name, 'tag_sets_id': tag_set['tag_sets_id']})

    return invalid_tag


def _add_user_story(db: DatabaseHandler, topic: dict, user: dict, topic_fetch_urls: list) -> dict:
    """Generate a story based on the given user, as returned by the twitter api."""
    content = f"{user['name']} ({user['screen_name']}): {user['description']}"
    title = f"{user['name']} ({user['screen_name']}) | Twitter"
    tweet_date = sql_now()
    url = f"https://twitter.com/{user['screen_name']}"

    story = generate_story(db=db, url=url, content=content, title=title, publish_date=tweet_date)
    add_to_topic_stories(db=db, story=story, topic=topic, link_mined=True)

    for topic_fetch_url in topic_fetch_urls:
        topic_fetch_url = _log_tweet_added(db, topic_fetch_url, story)
        try_update_topic_link_ref_stories_id(db, topic_fetch_url)

    # twitter user pages are undateable because there is never a consistent version of the page
    undateable_tag = _get_undateable_tag(db)
    db.query(
        """
            INSERT INTO stories_tags_map (stories_id, tags_id)
            VALUES (%(stories_id)s, %(tags_id)s)
            ON CONFLICT (stories_id, tags_id) DO NOTHING
        """,
        {
            'stories_id': story['stories_id'],
            'tags_id': undateable_tag['tags_id'],
        }
    )

    return story


def _try_fetch_users_chunk(db: DatabaseHandler, topic: Dict[str, Any], topic_fetch_urls: List[Dict[str, Any]]) -> None:
    """Fetch up to URLS_CHUNK_SIZE topic_fetch_urls from twitter api as users and add them as topic stories.

    Throw any errors up the stack.
    """
    url_lookup = {}
    for topic_fetch_url in topic_fetch_urls:
        screen_name = parse_screen_name_from_user_url(topic_fetch_url['url']).lower()
        url_lookup.setdefault(screen_name, [])
        url_lookup[screen_name].append(topic_fetch_url)

    screen_names = list(url_lookup.keys())

    log.info(f"fetching users for {len(screen_names)} screen_names ...")
    users = fetch_100_users(screen_names)

    for user in users:
        try:
            screen_name = user['screen_name'].lower()
            topic_fetch_urls = url_lookup[screen_name]
            del (url_lookup[screen_name])
        except KeyError:
            raise KeyError(f"can't find user '{user['screen_name']}' in urls: {screen_names}")

        content = f"{user['name']} {user['screen_name']} {user['description']}"
        if content_matches_topic(content, topic):
            _add_user_story(db, topic, user, topic_fetch_urls)
        else:
            [_log_content_match_failed(db, u) for u in topic_fetch_urls]

    for screen_name in url_lookup.keys():
        topic_fetch_urls = url_lookup[screen_name]
        [_log_tweet_missing(db, u) for u in topic_fetch_urls]


def _add_tweet_story(db: DatabaseHandler,
                     topic: Dict[str, Any],
                     tweet: dict,
                     topic_fetch_urls: List[Dict[str, Any]]) -> dict:
    """Generate a story based on the given tweet, as returned by the twitter api."""
    screen_name = tweet['user']['screen_name']
    content = tweet['text']
    title = f"{screen_name}: {content}"
    tweet_date = tweet['created_at']
    url = f"https://twitter.com/{screen_name}/status/{tweet['id']}"

    story = generate_story(db=db, url=url, content=content, title=title, publish_date=tweet_date)
    add_to_topic_stories(db=db, story=story, topic=topic, link_mined=True)

    for topic_fetch_url in topic_fetch_urls:
        topic_fetch_url = _log_tweet_added(db, topic_fetch_url, story)
        try_update_topic_link_ref_stories_id(db, topic_fetch_url)

    urls = get_tweet_urls(tweet)
    for url in urls:
        if skip_self_linked_domain_url(db, topic['topics_id'], story['url'], url):
            log.debug("skipping self linked domain url...")
            continue

        topic_link = {
            'topics_id': topic['topics_id'],
            'stories_id': story['stories_id'],
            'url': url,
        }

        db.create('topic_links', topic_link)
        increment_domain_links(db, topic_link)

    return story


def _try_fetch_tweets_chunk(db: DatabaseHandler,
                            topic: Dict[str, Any],
                            topic_fetch_urls: List[Dict[str, Any]]) -> None:
    """Fetch up to URLS_CHUNK_SIZE topic_fetch_urls from twitter api as statuses and add them as topic stories.

    Throw any errors up the stack.
    """
    status_lookup = {}
    for topic_fetch_url in topic_fetch_urls:
        status_id = parse_status_id_from_url(topic_fetch_url['url'])
        status_lookup.setdefault(status_id, [])
        status_lookup[status_id].append(topic_fetch_url)

    status_ids = list(status_lookup.keys())

    log.info(f"fetching tweets for {len(status_ids)} status_ids ...")
    tweets = fetch_100_tweets(status_ids)

    for tweet in tweets:
        try:
            topic_fetch_urls = status_lookup[str(tweet['id'])]
            del (status_lookup[str(tweet['id'])])
        except KeyError:
            raise KeyError(f"can't find tweet '{tweet['id']}' in ids: {status_ids}")

        if content_matches_topic(tweet['text'], topic):
            _add_tweet_story(db, topic, tweet, topic_fetch_urls)
        else:
            [_log_content_match_failed(db, u) for u in topic_fetch_urls]

    for status_id in status_lookup.keys():
        topic_fetch_urls = status_lookup[status_id]
        [_log_tweet_missing(db, u) for u in topic_fetch_urls]


def _call_function_on_url_chunks(db: DatabaseHandler,
                                 topic: Dict[str, Any],
                                 urls: List[Dict[str, Any]],
                                 chunk_function: Callable) -> None:
    """Call chunk_function on chunks of up to URLS_CHUNK_SIZE urls at a time.

    Catch any exceptions raised and save them in the topic_fetch_urls for the given chunk.
    """
    i = 0
    while i < len(urls):
        chunk_urls = urls[i:i + URLS_CHUNK_SIZE]

        try:
            chunk_function(db, topic, chunk_urls)
        except Exception as ex:
            log.warning(f"error fetching twitter data: {ex}")

            topic_fetch_urls_ids = [u['topic_fetch_urls_id'] for u in urls]
            db.query("""
                UPDATE topic_fetch_urls SET
                    state = %(state)s,
                    message = %(message)s
                WHERE
                    topics_id = %(topics_id)s AND
                    topic_fetch_urls_id = ANY(%(topic_fetch_urls_ids)s)
            """, {
                'state': FETCH_STATE_PYTHON_ERROR,
                'message': str(ex),
                'topics_id': topic['topics_id'],
                'topic_fetch_urls_ids': topic_fetch_urls_ids,
            })

        i += URLS_CHUNK_SIZE


def _split_urls_into_users_and_statuses(topic_fetch_urls: List[Dict[str, Any]]) -> tuple:
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
                raise McFetchTwitterUrlsDataException(f"url '{url}' is not a twitter status or a twitter user")

    return user_urls, status_urls


def fetch_twitter_urls(db: DatabaseHandler, topics_id: int, topic_fetch_urls_ids: List[int]) -> None:
    """Fetch topic_fetch_urls from twitter api as statuses and users in chunks of up to 100."""
    if len(topic_fetch_urls_ids) == 0:
        return

    topic_fetch_urls = db.query("""
        SELECT *
        FROM topic_fetch_urls
        WHERE
            topics_id = %(topics_id)s AND
            topic_fetch_urls_id = ANY(%(topic_fetch_urls_ids)s)
    """, {
        'topics_id': topics_id,
        'topic_fetch_urls_ids': topic_fetch_urls_ids,
    }).hashes()

    topic = db.require_by_id('topics', topics_id)

    (user_urls, status_urls) = _split_urls_into_users_and_statuses(topic_fetch_urls)

    _call_function_on_url_chunks(db, topic, user_urls, _try_fetch_users_chunk)
    _call_function_on_url_chunks(db, topic, status_urls, _try_fetch_tweets_chunk)


def fetch_twitter_urls_update_state(db: DatabaseHandler,
                                    topics_id: int,
                                    topic_fetch_urls_ids: List[int]) -> None:
    """Try fetch_twitter_urls(), update state."""
    try:
        fetch_twitter_urls(db=db, topics_id=topics_id, topic_fetch_urls_ids=topic_fetch_urls_ids)
    except Exception as ex:
        log.error(f"Error while fetching URL with ID {topic_fetch_urls_ids}: {ex}")
        db.query("""
            UPDATE topic_fetch_urls SET
                state = %(state)s,
                message = %(message)s,
                fetch_date = NOW()
            WHERE
                topics_id = %(topics_id)s AND
                topic_fetch_urls_id = ANY(%(topic_fetch_urls_ids)s)
        """, {
            'state': FETCH_STATE_PYTHON_ERROR,
            'message': traceback.format_exc(),
            'topics_id': topics_id,
            'topic_fetch_urls_ids': topic_fetch_urls_ids,
        })
