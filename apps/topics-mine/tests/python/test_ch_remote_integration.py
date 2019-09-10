from mediawords.db import connect_to_db

from .remote_integration_tests import run_remote_integration_tests

# test crimson hexagon monitor id
TEST_MONITOR_ID = 4667493813


def test_ch_remote_integration() -> None:
    """Test ch remote integration."""
    db = connect_to_db()
    run_remote_integration_tests(db=db, source='crimson_hexagon', query=str(TEST_MONITOR_ID), day='2016-01-01')
