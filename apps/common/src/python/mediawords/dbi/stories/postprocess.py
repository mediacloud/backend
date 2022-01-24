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
    if isinstance(stories_id, bytes):
        stories_id = decode_object_from_bytes_if_needed(stories_id)
    stories_id = int(stories_id)

    log.debug(f"Marking story ID {stories_id} as processed...")

    try:
        db.query(
            """
            INSERT INTO processed_stories (stories_id)
            VALUES (%(stories_id)s)
            ON CONFLICT (stories_id) DO NOTHING
            """,
            {'stories_id': stories_id}
        )
    except Exception as ex:
        log.warning(f"Unable to insert story ID {stories_id} into 'processed_stories': {ex}")
        return False
    else:
        return True
