from mediawords.db import DatabaseHandler
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McMediumIsLockedException(Exception):
    """medium_is_locked() exception.

    If thrown, doesn't mean that medium is (un)locked, just that an error has occurred while testing if it is."""
    pass


def medium_is_locked(db: DatabaseHandler, media_id: int) -> bool:
    """Use a new blocking check to see if the given media_id is locked by a postgres advisory lock (used within
    _insert_story_sentences below). Return True if it is locked, False otherwise."""

    if isinstance(media_id, bytes):
        media_id = decode_object_from_bytes_if_needed(media_id)
    media_id = int(media_id)

    got_lock = db.query("SELECT pg_try_advisory_lock(%(media_id)s)", {'media_id': media_id}).flat()[0]
    if got_lock:
        db.query("SELECT pg_advisory_unlock(%(media_id)s)", {'media_id': media_id})

    return not got_lock
