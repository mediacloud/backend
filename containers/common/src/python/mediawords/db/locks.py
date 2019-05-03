"""Constants and routines for handling advisory postgres locks."""

import mediawords.db
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

"""
This package just has constants that can be passed to the first value of the postgres pg_advisory_*lock functions.
If you are using an advistory lock, you should use the two key version and use a constant from this package to
avoid conflicts.
"""

# locks to make sure we are not mining or snapshotting a topic in more than one process at a time
LOCK_TYPES = {
    'test-a': 10,
    'test-b': 11,
    'MediaWords::Job::TM::MineTopic': 12,
    'MediaWords::Job::TM::SnapshotTopic': 13,
    'MediaWords::TM::Media::media_normalized_urls': 14,
    'MediaWords::Crawler::Engine::run_fetcher': 15
}


class McDBLocksException(Exception):
    """Default exception for package."""

    pass


def get_session_lock(db: mediawords.db.DatabaseHandler, lock_type: str, lock_id: int, wait: bool = False) -> bool:
    """Get a postgres advisory lock with the lock_type and lock_id as the two keys.

    Arguments:
    db - db handle
    lock_type - must be in LOCK_TYPES dict above
    lock_id - id for the particular lock within the type
    wait - if true, block while waiting for the lock, else return false if the lock is not available

    Returns:
    True if the lock is available
    """
    lock_type = str(decode_object_from_bytes_if_needed(lock_type))

    if isinstance(lock_id, bytes):
        lock_id = decode_object_from_bytes_if_needed(lock_id)
    lock_id = int(lock_id)

    if isinstance(wait, bytes):
        wait = decode_object_from_bytes_if_needed(wait)
    wait = bool(wait)

    log.debug("trying for lock: %s, %d" % (lock_type, lock_id))

    if lock_type not in LOCK_TYPES:
        raise McDBLocksException("lock type not in LOCK_TYPES: %s" % lock_type)

    lock_type_id = LOCK_TYPES[lock_type]

    if wait:
        db.query("select pg_advisory_lock(%(a)s, %(b)s)", {'a': lock_type_id, 'b': lock_id})
        return True
    else:
        r = db.query("select pg_try_advisory_lock(%(a)s, %(b)s) as locked", {'a': lock_type_id, 'b': lock_id}).hash()
        return r['locked']


def release_session_lock(db: mediawords.db.DatabaseHandler, lock_type: str, lock_id: int) -> None:
    """Release the postgres advisory lock if it is held."""
    lock_type = str(decode_object_from_bytes_if_needed(lock_type))

    if isinstance(lock_id, bytes):
        lock_id = decode_object_from_bytes_if_needed(lock_id)
    lock_id = int(lock_id)

    if lock_type not in LOCK_TYPES:
        raise McDBLocksException("lock type not in LOCK_TYPES: %s" % lock_type)

    lock_type_id = LOCK_TYPES[lock_type]

    db.query("select pg_advisory_unlock(%(a)s, %(b)s)", {'a': lock_type_id, 'b': lock_id})


def list_session_locks(db: mediawords.db.DatabaseHandler, lock_type: str) -> list:
    """Return a list of all locked ids for the given lock_type."""
    lock_type = str(decode_object_from_bytes_if_needed(lock_type))

    if lock_type not in LOCK_TYPES:
        raise McDBLocksException("lock type not in LOCK_TYPES: %s" % lock_type)

    lock_type_id = LOCK_TYPES[lock_type]

    return db.query(
        "select objid from pg_locks where locktype = 'advisory' and classid = %(a)s",
        {'a': lock_type_id}).flat()
