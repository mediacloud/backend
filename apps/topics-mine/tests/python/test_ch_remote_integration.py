from mediawords.db import connect_to_db

from .remote_integration import validate_remote_integration

# test crimson hexagon monitor id
TEST_MONITOR_ID = 4667493813


def test_ch_remote_integration() -> None:
    """Test ch remote integration."""
    db = connect_to_db()
    validate_remote_integration(db=db, source='crimson_hexagon', query=str(TEST_MONITOR_ID), day='2016-01-01')
