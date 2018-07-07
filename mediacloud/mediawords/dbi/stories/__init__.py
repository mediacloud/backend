import datetime
from typing import List, Optional

from mediawords.db import DatabaseHandler
from mediawords.util.html import html_strip
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import get_sql_date_from_epoch
from mediawords.util.url import get_url_host

log = create_logger(__name__)


class McAddStoryException(Exception):
    """add_story() exception."""
    pass


def mark_as_processed(db: DatabaseHandler, stories_id: int) -> bool:
    """Mark the story as processed by inserting an entry into 'processed_stories'. Return True on success."""

    # FIXME upsert instead of inserting a potential duplicate

    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)

    stories_id = int(stories_id)

    log.debug("Marking story ID %d as processed..." % stories_id)

    try:
        db.insert(table='processed_stories', insert_hash={'stories_id': stories_id})
    except Exception as ex:
        log.warning("Unable to insert story ID %d into 'processed_stories': %s" % (stories_id, str(ex),))
        return False
    else:
        return True


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


def combine_story_title_description_text(story_title: Optional[str],
                                         story_description: Optional[str],
                                         download_texts: List[str]) -> str:
    """Get the combined story title, story description, and download text of the story in a consistent way."""
    story_title = decode_object_from_bytes_if_needed(story_title)
    story_description = decode_object_from_bytes_if_needed(story_description)
    download_texts = decode_object_from_bytes_if_needed(download_texts)

    if story_title is None:
        story_title = ''

    if story_description is None:
        story_description = ''

    return "\n***\n\n".join([html_strip(story_title), html_strip(story_description)] + download_texts)


def get_extracted_text(db: DatabaseHandler, story: dict) -> str:
    """Return the concatenated download_texts associated with the story."""

    story = decode_object_from_bytes_if_needed(story)

    download_texts = db.query("""
        SELECT dt.download_text
        FROM downloads AS d,
             download_texts AS dt
        WHERE dt.downloads_id = d.downloads_id
          AND d.stories_id = %(stories_id)s
        ORDER BY d.downloads_id
    """, {'stories_id': story['stories_id']}).flat()

    return ".\n\n".join(download_texts)


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


def __get_full_text_from_rss(story: dict) -> str:
    story = decode_object_from_bytes_if_needed(story)

    story_title = story.get('title', '')
    story_description = story.get('description', '')

    return "\n\n".join([html_strip(story_title), html_strip(story_description)])


def get_text_for_word_counts(db: DatabaseHandler, story: dict) -> str:
    """Like get_text(), but it doesn't include both title + description and the extracted text.

    This is what is used to fetch text to generate story_sentences, which eventually get imported into Solr.

    If the text of the story ends up being shorter than the description, return the title + description instead of the
    story text (some times the extractor falls down and we end up with better data just using the title + description.
    """
    story = decode_object_from_bytes_if_needed(story)

    if story['full_text_rss']:
        story_text = __get_full_text_from_rss(story)
    else:
        story_text = get_extracted_text(db=db, story=story)

    story_description = story.get('description', '')

    if story_text is None:
        story_text = ''
    if story_description is None:
        story_description = ''

    if len(story_text) == 0 or len(story_text) < len(story_description):
        story_text = html_strip(story['title'])
        if story['description']:

            story_text = story_text.strip()
            if not story_text.endswith('.'):
                story_text += '.'

            story_text += html_strip(story['description'])

    return story_text


def get_text(db: DatabaseHandler, story: dict) -> str:
    """Get the concatenation of the story title and description and all of the download_texts associated with the story
    in a consistent way.

    If full_text_rss is True for the medium, just return the concatenation of the story title and description.
    """

    story = decode_object_from_bytes_if_needed(story)

    if story['full_text_rss']:
        return __get_full_text_from_rss(story=story)

    download_texts = db.query("""
        SELECT download_text
        FROM download_texts AS dt,
             downloads AS d
        WHERE d.downloads_id = dt.downloads_id
          AND d.stories_id = %(stories_id)s
        ORDER BY d.downloads_id ASC
    """, {'stories_id': story['stories_id']}).flat()

    pending_downloads = db.query("""
        SELECT downloads_id
        FROM downloads
        WHERE extracted = 'f'
          AND stories_id = %(stories_id)s
          AND type = 'content'
    """, {'stories_id': story['stories_id']}).hashes()

    if pending_downloads is not None and len(pending_downloads) > 0:
        download_texts.append("(downloads pending extraction)")

    story_text = combine_story_title_description_text(
        story_title=story['title'],
        story_description=story['description'],
        download_texts=download_texts,
    )

    return story_text


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
