import datetime
from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import get_sql_date_from_epoch
from mediawords.util.url import get_url_host

log = create_logger(__name__)

MAX_URL_LENGTH = 1024
MAX_TITLE_LENGTH = 1024


class McAddStoryException(Exception):
    """add_story() exception."""
    pass


def is_new(db: DatabaseHandler, story: dict) -> bool:
    """Return true if this story should be considered new for the given media source.

    This is used to determine whether to add a new story for a feed item URL.

    A story is new if no story with the same URL or GUID exists in the same media source and if no story exists with the
    same title in the same media source in the same calendar day.
    """

    story = decode_object_from_bytes_if_needed(story)

    if story['title'] == '(no title)':
        return False

    db_story = db.query("""
        SELECT *
        FROM stories
        WHERE guid = %(guid)s
          AND media_id = %(media_id)s
    """, {
        'guid': story['guid'],
        'media_id': story['media_id'],
    }).hash()
    if db_story:
        return False

    db_story = db.query("""
        SELECT 1
        FROM stories
        WHERE md5(title) = md5(%(title)s)
          AND media_id = %(media_id)s

          -- We do the goofy " + interval '1 second'" to force postgres to use the stories_title_hash index
          AND date_trunc('day', publish_date)  + interval '1 second'
            = date_trunc('day', %(publish_date)s::date) + interval '1 second'

        -- FIXME why FOR UPDATE?
        FOR UPDATE
    """, {
        'title': story['title'],
        'media_id': story['media_id'],
        'publish_date': story['publish_date'],
    }).hash()
    if db_story:
        return False

    return True


def add_story(db: DatabaseHandler, story: dict, feeds_id: int, skip_checking_if_new: bool = False) -> Optional[dict]:
    """If the story is new, add story to the database with the feed of the download as story feed.

    Returns created story or None if story wasn't created.
    """

    story = decode_object_from_bytes_if_needed(story)
    if isinstance(feeds_id, bytes):
        feeds_id = decode_object_from_bytes_if_needed(feeds_id)
    feeds_id = int(feeds_id)
    if isinstance(skip_checking_if_new, bytes):
        skip_checking_if_new = decode_object_from_bytes_if_needed(skip_checking_if_new)
    skip_checking_if_new = bool(int(skip_checking_if_new))

    if db.in_transaction():
        raise McAddStoryException("add_story() can't be run from within transaction.")

    db.begin()

    db.query("LOCK TABLE stories IN ROW EXCLUSIVE MODE")

    if not skip_checking_if_new:
        if not is_new(db=db, story=story):
            log.debug("Story '{}' is not new.".format(story['url']))
            db.commit()
            return None

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

    db.find_or_create(
        table='feeds_stories_map',
        insert_hash={
            'stories_id': story['stories_id'],
            'feeds_id': feeds_id,
        }
    )

    db.commit()

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

    if story is not None:
        _create_child_download_for_story(db=db, story=story, parent_download=parent_download)

    return story
