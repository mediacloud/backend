import datetime
from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads import extract_and_create_download_text
from mediawords.dbi.stories.extractor_arguments import PyExtractorArguments
from mediawords.dbi.stories.process import process_extracted_story
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import get_sql_date_from_epoch
from mediawords.util.url import get_url_host, normalize_url_lossy

log = create_logger(__name__)

MAX_URL_LENGTH = 1024
MAX_TITLE_LENGTH = 1024


class McAddStoryException(Exception):
    """add_story() exception."""
    pass


def insert_story_urls(db: DatabaseHandler, story: dict, url: str) -> None:
    """Insert the url and the normalize_url_lossy() version of the url into story_urls."""
    urls = (url, normalize_url_lossy(url))

    for url in set(urls):
        db.query(
            """
            insert into story_urls (stories_id, url) values (%(a)s, %(b)s) on conflict (url, stories_id) do nothing
            """,
            {'a': story['stories_id'], 'b': url})


def _get_story_url_variants(story: dict) -> list:
    """Return a list of the unique set of the story url and guid and their normalize_url_lossy() versions."""
    urls = list({story['url'], normalize_url_lossy(story['url']), story['guid'], normalize_url_lossy(story['guid'])})

    return urls


def find_dup_story(db: DatabaseHandler, story: dict) -> bool:
    """Return existing duplicate story within the same media source.

    Search for a story that is a duplicate of the given story.  A story is a duplicate if it shares the same media
    source and:

    * has the same normalized title and has a publish_date within the same calendar week
    * has a normalized guid or url that is the same as the normalized guid or url

    If a dup story is found, insert the url and guid into the story_urls table.

    Return the found story or None if no story is found.
    """
    story = decode_object_from_bytes_if_needed(story)

    if story['title'] == '(no title)':
        return None

    urls = _get_story_url_variants(story)

    db_story = db.query("""
        SELECT s.*
        FROM stories s
        WHERE
            (s.guid = any( %(urls)s ) or s.url = any( %(urls)s)) and
            media_id = %(media_id)s
    """, {
        'urls': urls,
        'media_id': story['media_id'],
    }).hash()
    if db_story:
        return db_story

    # make sure that postgres uses the story_urls_url index
    db.query("create temporary table _u as select stories_id from story_urls where url = any( %(a)s )", {'a': urls})
    db_story = db.query(
        "select * from stories s join _u u using ( stories_id ) where media_id = %(a)s order by stories_id limit 1",
        {'a': story['media_id']}).hash()
    db.query("drop table _u")
    if db_story:
        return db_story

    db_story = db.query("""
        SELECT *
        FROM stories
        WHERE
            (md5(title) = md5(%(title)s) OR
                normalized_title_hash = md5( get_normalized_title( %(title)s, %(media_id)s ) )::uuid)
            AND media_id = %(media_id)s

          -- We do the goofy " + interval '1 second'" to force postgres to use the stories_title_hash index
          AND date_trunc('day', publish_date)  + interval '1 second'
            = date_trunc('day', %(publish_date)s::date) + interval '1 second'
    """, {
        'title': story['title'],
        'media_id': story['media_id'],
        'publish_date': story['publish_date'],
    }).hash()

    if db_story:
        [insert_story_urls(db, db_story, u) for u in (story['url'], story['guid'])]

        return db_story

    return None


def add_story(db: DatabaseHandler, story: dict, feeds_id: int) -> Optional[dict]:
    """Return an existing dup story if it matches the url, guid, or title; otherwise, add a new story and return it.

    Returns found or created story. Adds an is_new = True story if the story was created by the call.
    """

    story = decode_object_from_bytes_if_needed(story)
    if isinstance(feeds_id, bytes):
        feeds_id = decode_object_from_bytes_if_needed(feeds_id)
    feeds_id = int(feeds_id)

    if db.in_transaction():
        raise McAddStoryException("add_story() can't be run from within transaction.")

    db.begin()

    db.query("LOCK TABLE stories IN ROW EXCLUSIVE MODE")

    db_story = find_dup_story(db, story)
    if db_story:
        log.debug("found existing dup story: %s [%s]" % (story['title'], story['url']))
        db.commit()
        return db_story

    medium = db.find_by_id(table='media', object_id=story['media_id'])

    if story.get('full_text_rss', None) is None:
        story['full_text_rss'] = medium.get('full_text_rss', False) or False
        if len(story.get('description', '')) == 0:
            story['full_text_rss'] = False

    try:
        story = db.create(table='stories', insert_hash=story)
    except Exception as ex:
        db.rollback()

        # FIXME get rid of this, replace with native upsert on "stories_guid" unique constraint
        if 'unique constraint \"stories_guid' in str(ex):
            log.warning(
                "Failed to add story for '{}' to GUID conflict (guid = '{}')".format(story['url'], story['guid'])
            )
            return None

        else:
            raise McAddStoryException("Error adding story: {}\nStory: {}".format(str(ex), str(story)))

    story['is_new'] = True

    [insert_story_urls(db, story, u) for u in (story['url'], story['guid'])]

    # on conflict does not work with partitioned feeds_stories_map
    db.query(
        """
        insert into feeds_stories_map_p ( feeds_id, stories_id )
            select %(a)s, %(b)s where not exists (
                select 1 from feeds_stories_map where feeds_id = %(a)s and stories_id = %(b)s )
        """,
        {'a': feeds_id, 'b': story['stories_id']})

    db.commit()

    log.debug("added story: %s" % story['url'])

    return story


def _create_child_download_for_story(db: DatabaseHandler, story: dict, parent_download: dict) -> None:
    """Create a pending download for the story's URL."""
    story = decode_object_from_bytes_if_needed(story)
    parent_download = decode_object_from_bytes_if_needed(parent_download)

    download = {
        'feeds_id': parent_download['feeds_id'],
        'stories_id': story['stories_id'],
        'parent': parent_download['downloads_id'],
        'url': story['url'],
        'host': get_url_host(story['url']),
        'type': 'content',
        'sequence': 1,
        'state': 'pending',
        'priority': parent_download['priority'],
        'extracted': False,
    }

    content_delay = db.query("""
        SELECT content_delay
        FROM media
        WHERE media_id = %(media_id)s
    """, {'media_id': story['media_id']}).flat()[0]
    if content_delay:
        # Delay download of content this many hours. his is useful for sources that are likely to significantly change
        # content in the hours after it is first published.
        now = int(datetime.datetime.now(datetime.timezone.utc).timestamp())
        download_at_timestamp = now + (content_delay * 60 * 60)
        download['download_time'] = get_sql_date_from_epoch(download_at_timestamp)

    db.create(table='downloads', insert_hash=download)


def add_story_and_content_download(db: DatabaseHandler, story: dict, parent_download: dict) -> Optional[dict]:
    """If the story is new, add it to the database and also add a pending download for the story content."""
    story = decode_object_from_bytes_if_needed(story)
    parent_download = decode_object_from_bytes_if_needed(parent_download)

    story = add_story(db=db, story=story, feeds_id=parent_download['feeds_id'])

    if story.get('is_new', False):
        _create_child_download_for_story(db=db, story=story, parent_download=parent_download)

    return story


def extract_and_process_story(db: DatabaseHandler,
                              story: dict,
                              extractor_args: PyExtractorArguments = PyExtractorArguments()) -> None:
    """Extract all of the downloads for the given story and then call process_extracted_story()."""

    story = decode_object_from_bytes_if_needed(story)

    stories_id = story['stories_id']

    use_transaction = not db.in_transaction()
    if use_transaction:
        db.begin()

    log.debug("Fetching downloads for story {}...".format(stories_id))
    downloads = db.query("""
        SELECT *
        FROM downloads
        WHERE stories_id = %(stories_id)s
          AND type = 'content'
        ORDER BY downloads_id ASC
    """, {'stories_id': stories_id}).hashes()

    # MC_REWRITE_TO_PYTHON: Perlism
    if downloads is None:
        downloads = []

    for download in downloads:
        log.debug("Extracting download {} for story {}...".format(download['downloads_id'], stories_id))
        extract_and_create_download_text(db=db, download=download, extractor_args=extractor_args)

    log.debug("Processing extracted story {}...".format(stories_id))
    process_extracted_story(db=db, story=story, extractor_args=extractor_args)

    if use_transaction:
        db.commit()
