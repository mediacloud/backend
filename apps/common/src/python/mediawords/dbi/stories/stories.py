from typing import Optional, List, Dict, Any

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.url import normalize_url_lossy

log = create_logger(__name__)

MAX_URL_LENGTH = 1024
MAX_TITLE_LENGTH = 1024


class McAddStoryException(Exception):
    """add_story() exception."""
    pass


class _McAddStoryDuplicateGUIDException(Exception):
    """Internal exception thrown when story with a specific GUID already exists."""
    pass


def insert_story_urls(db: DatabaseHandler, story: dict, url: str) -> None:
    """Insert the url and the normalize_url_lossy() version of the url into story_urls."""
    urls = (url, normalize_url_lossy(url))

    for url in set(urls):

        # FIXME some URLs are overly encoded, e.g.:
        #
        # http://dinamani.com/india/2020/feb/19/%E0%AE%85%E0%AE%AF%E0%AF%8B%E0
        # %AE%A4%E0%AF%8D%E0%AE%A4%E0%AE%BF%E0%AE%AF%E0%AE%BF%E0%AE%B2%E0%AF
        # %8D-%E0%AE%AA%E0%AE%BE%E0%AE%AA%E0%AE%BE%E0%AF%8D-%E0%AE%AE%E0%AE%9A
        # %E0%AF%82%E0%AE%A4%E0%AE%BF%E0%AE%AF%E0%AF%88-%E0%AE%9A%E0%AF%81%E0
        # %AE%B1%E0%AF%8D%E0%AE%B1%E0%AE%BF%E0%AE%AF%E0%AF%81%E0%AE%B3%E0%AF
        # %8D%E0%AE%B3-%E0%AE%AE%E0%AE%AF%E0%AE%BE%E0%AE%A9%E0%AE%A4%E0%AF%8D
        # %E0%AE%A4%E0%AF%88-%E0%AE%B5%E0%AE%BF%E0%AE%9F%E0%AF%8D%E0%AE%9F%E0
        # %AF%81%E0%AE%B5%E0%AF%88%E0%AE%95%E0%AF%8D%E0%AE%95-%E0%AE%B5%E0%AF
        # %87%E0%AE%A3%E0%AF%8D%E0%AE%9F%E0%AF%81%E0%AE%AE%E0%AF%8D-%E0%AE%B0
        # %E0%AE%BE%E0%AE%AE%E0%AE%BE%E0%AF%8D-%E0%AE%95%E0%AF%8B%E0%AE%AF%E0
        # %AE%BF%E0%AE%B2%E0%AF%8D-%E0%AE%85%E0%AE%B1%E0%AE%95%E0%AF%8D%E0%AE
        # %95%E0%AE%9F%E0%AF%8D%E0%AE%9F%E0%AE%B3%E0%AF%88%E0%AE%95%E0%AF%8D
        # %E0%AE%95%E0%AF%81-%E0%AE%AE%E0%AF%82%E0%AE%A4%E0%AF%8D%E0%AE%A4-
        # %E0%AE%B5%E0%AE%B4%E0%AE%95%E0%AF%8D%E0%AE%95%E0%AF%81%E0%AE%B0%E0
        # %AF%88%E0%AE%9E%E0%AE%BE%E0%AF%8D-%E0%AE%95%E0%AE%9F%E0%AE%BF%E0%AE
        # %A4%E0%AE%AE%E0%AF%8D-3361308.html
        #
        # We might benefit from decoding the path in such URLs so that it fits
        # within 1024 characters, and perhaps more importantly, the
        # deduplication works better:
        #
        # http://dinamani.com/india/2020/feb/19/அயோத்தியில்-பாபா்-மசூதியை-சுற்றி
        # யுள்ள-மயானத்தை-விட்டுவைக்க-வேண்டும்-ராமா்-கோயில்-அறக்கட்டளைக்கு-மூத்த-வழ
        # க்குரைஞா்-கடிதம்-3361308.html
        if len(url) <= MAX_URL_LENGTH:
            db.query(
                """
                INSERT INTO story_urls (stories_id, url)
                VALUES (%(stories_id)s, %(url)s)
                ON CONFLICT (stories_id, url) DO NOTHING
                """,
                {'stories_id': story['stories_id'], 'url': url}
            )


def _get_story_url_variants(story: dict) -> List[str]:
    """Return a list of the unique set of the story url and guid and their normalize_url_lossy() versions."""
    urls = sorted(list({
        story['url'],
        normalize_url_lossy(story['url']),
        story['guid'],
        normalize_url_lossy(story['guid']),
    }))

    return urls


def _find_dup_stories(db: DatabaseHandler, story: dict) -> List[Dict[str, Any]]:
    """Return existing duplicate stories within the same media source.

    Search for stories that are duplicates of the given story.  A story is a duplicate if it shares the same media
    source and:

    * has the same normalized title and has a publish_date within the same calendar week; or
    * has a normalized guid or url that is the same as the normalized guid or url

    If a dup story is found, insert the url and guid into the story_urls table.

    Return duplicate stories or an empty list if no duplicate stories were found.
    """
    story = decode_object_from_bytes_if_needed(story)

    if story['title'] == '(no title)':
        return []

    urls = _get_story_url_variants(story)

    db_stories = db.query("""
        SELECT *
        FROM stories
        WHERE
            (
                guid = ANY(%(urls)s) OR url = ANY(%(urls)s)
            ) AND
            media_id = %(media_id)s
        ORDER BY stories_id
    """, {
        'urls': urls,
        'media_id': story['media_id'],
    }).hashes()
    if db_stories:
        return db_stories

    db_stories = db.query("""

        -- Make sure that postgres uses the story_urls_url index
        WITH matching_stories AS (
            SELECT stories_id
            FROM story_urls
            WHERE url = ANY(%(story_urls)s)
        )

        SELECT *
        FROM stories
            JOIN matching_stories USING (stories_id)
        WHERE media_id = %(media_id)s
        ORDER BY stories_id

    """, {
        'story_urls': urls,
        'media_id': story['media_id'],
    }).hashes()

    if db_stories:
        return db_stories

    db_stories = db.query("""
        -- noinspection SqlResolve @ routine/"get_normalized_title"
        SELECT *
        FROM stories
        WHERE
            (md5(title) = md5(%(title)s) OR
                normalized_title_hash = md5( get_normalized_title( %(title)s, %(media_id)s ) )::uuid)
            AND media_id = %(media_id)s

          -- We do the goofy " + interval '1 second'" to force postgres to use the stories_title_hash index
          AND date_trunc('day', publish_date)  + interval '1 second'
            = date_trunc('day', %(publish_date)s::date) + interval '1 second'
        ORDER BY stories_id
    """, {
        'title': story['title'],
        'media_id': story['media_id'],
        'publish_date': story['publish_date'],
    }).hashes()

    if db_stories:
        for db_story in db_stories:
            [insert_story_urls(db, db_story, u) for u in (story['url'], story['guid'])]

        return db_stories

    return []


def add_story(db: DatabaseHandler, story: dict, feeds_id: int) -> Optional[dict]:
    """Return an existing dup story if it matches the url, guid, or title; otherwise, add a new story and return it.

    Returns found or created story. Adds an is_new = True story if the story was created by the call.
    """

    story = decode_object_from_bytes_if_needed(story)
    if isinstance(feeds_id, bytes):
        feeds_id = decode_object_from_bytes_if_needed(feeds_id)
    feeds_id = int(feeds_id)

    # PostgreSQL is not a fan of NULL bytes in strings
    for key in story.keys():
        if isinstance(story[key], str):
            story[key] = story[key].replace('\x00', '')

    medium = db.find_by_id(table='media', object_id=story['media_id'])

    if story.get('full_text_rss', None) is None:
        story['full_text_rss'] = medium.get('full_text_rss', False) or False

        # Description can be None
        if not story.get('description', None):
            story['full_text_rss'] = False

    if len(story['url']) >= MAX_URL_LENGTH:
        log.error(f"Story's URL is too long: {story['url']}")
        return None

    db_stories = _find_dup_stories(db, story)
    if db_stories:
        first_story = db_stories[0]
        log.debug(f"Found one or more duplicate stories: {first_story['title']} [{first_story['url']}]")
        return first_story

    # After sharding stories.guid no longer can have a UNIQUE index so we can no longer do an atomic upsert, and
    # pre-atomic PostgreSQL upserts (INSERT INTO ... SELECT ... WHERE NOT EXISTS) have race conditions. So instead here
    # we insert a new row, check for "duplicate stories" again, find out how many we have, and if we have more than one
    # (i.e. something managed to get inserted while we were doing our own insert), we get rid of the row that we've just
    # added
    try:
        inserted_story = db.create(table='stories', insert_hash=story)
    except Exception as ex:
        raise McAddStoryException(f"Error while adding story: {ex}\nStory: {story}")

    db_stories = _find_dup_stories(db, story)

    if len(db_stories) == 0:
        raise McAddStoryException(f"Story got added but we can't find it now; story: {story}")

    elif len(db_stories) == 1:
        story = inserted_story
        story['is_new'] = True

    elif len(db_stories) > 1:
        db.query("""
            DELETE FROM stories
            WHERE stories_id = %(stories_id)s
        """, {
            'stories_id': inserted_story['stories_id'],
        })
        story = db_stories[0]

    [insert_story_urls(db, story, u) for u in (story['url'], story['guid'])]

    db.query("""
        INSERT INTO feeds_stories_map (feeds_id, stories_id)
        VALUES (%(a)s, %(b)s)
        ON CONFLICT (feeds_id, stories_id) DO NOTHING
    """, {
        'a': feeds_id,
        'b': story['stories_id'],
    })

    log.debug(f"Added story: {story['url']}")

    return story
