"""Test mediawords.db.locks"""

from mediawords.db import connect_to_db
from mediawords.db.locks import get_session_lock, release_session_lock, list_session_locks


def test_locks() -> None:
    """Test get_session_lock and release_session_lock."""
    db1 = connect_to_db()
    db2 = connect_to_db()

    assert db1 != db2

    assert get_session_lock(db1, 'test-a', 1)

    assert list_session_locks(db1, 'test-a') == [1]

    assert not get_session_lock(db2, 'test-a', 1, wait=False)

    assert get_session_lock(db2, 'test-a', 2, wait=False)
    assert sorted(list_session_locks(db2, 'test-a')) == [1, 2]
    release_session_lock(db2, 'test-a', 2)

    assert get_session_lock(db2, 'test-b', 1, wait=False)
    assert list_session_locks(db2, 'test-b') == [1]
    release_session_lock(db2, 'test-b', 1)

    release_session_lock(db1, 'test-a', 1)
    assert get_session_lock(db2, 'test-a', 1)
    assert list_session_locks(db2, 'test-a') == [1]
