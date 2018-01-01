from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def story_is_english_and_has_sentences(db: DatabaseHandler, stories_id: int) -> bool:
    """Check if story can be annotated."""

    # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)

    stories_id = int(stories_id)

    story = db.query("""
        SELECT story_is_english_and_has_sentences
        FROM story_is_english_and_has_sentences(%(stories_id)s)
    """, {'stories_id': stories_id}).hash()

    if story is not None and int(story['story_is_english_and_has_sentences']) == 1:
        return True
    else:
        return False


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
