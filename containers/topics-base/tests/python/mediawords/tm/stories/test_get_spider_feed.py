from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium

from mediawords.tm.stories import get_spider_feed, SPIDER_FEED_NAME


def test_get_spider_feed():
    """Test get_spider_feed()."""
    db = connect_to_db()

    medium = create_test_medium(db, 'foo')

    feed = get_spider_feed(db, medium)

    assert feed['name'] == SPIDER_FEED_NAME
    assert feed['media_id'] == medium['media_id']
    assert feed['active'] is False

    assert get_spider_feed(db, medium)['feeds_id'] == feed['feeds_id']
