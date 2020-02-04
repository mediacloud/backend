import datetime
from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.dbi.stories.stories import add_story
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import get_sql_date_from_epoch
from mediawords.util.url import get_url_host


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
