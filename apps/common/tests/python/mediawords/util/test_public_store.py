import mediawords.db
from mediawords.util.public_store import *
from mediawords.util.web.user_agent import UserAgent

def test_store_fetch() -> None:
    """Test that we can store and fetch content on s3."""
    db = mediawords.db.connect_to_db()

    test_content = 'foo bar baz bat'.encode('utf-8')
    test_content_id = 123456
    test_content_type = 'text/plain'

    store_content(db, TIMESPAN_MAPS_TYPE, test_content_id, test_content, test_content_type)

    got_content = fetch_content(db, TIMESPAN_MAPS_TYPE, test_content_id)

    assert got_content == test_content

    url = get_content_url(db, TIMESPAN_MAPS_TYPE, test_content_id)
