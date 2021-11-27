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

    log.debug(f"Marking story ID {stories_id} as processed...")

    try:

        # MC_CITUS_SHARDING_UPDATABLE_VIEW_HACK: upserts don't work on an
        # updatable view, and we can't upsert directly into the sharded table
        # as the duplicate row might already exist in the unsharded one;
        # therefore, we test the unsharded table once for whether the row
        # exists and do an upsert to a sharded table -- the row won't start
        # suddenly existing in an essentially read-only unsharded table so this
        # should be safe from race conditions. After migrating rows, one can
        # reset this statement to use a native upsert
        row_exists = db.query(
            """
            SELECT 1
            FROM processed_stories
            WHERE stories_id = %(stories_id)s
            """,
            {'stories_id': stories_id}
        ).hash()
        if not row_exists:
            db.query(
                """
                INSERT INTO sharded_public.processed_stories (stories_id)
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
