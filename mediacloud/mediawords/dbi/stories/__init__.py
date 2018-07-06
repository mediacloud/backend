from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


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
