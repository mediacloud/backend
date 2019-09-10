from mediawords.db import connect_to_db

from .remote_integration_tests import run_remote_integration_tests


def test_archive_remote_integration() -> None:
    """Test archive.org remote integration."""
    db = connect_to_db()
    run_remote_integration_tests(db=db, source='archive_org', query='harvard', day='2019-01-01')
