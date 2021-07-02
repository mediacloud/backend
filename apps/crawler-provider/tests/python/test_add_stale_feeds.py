import time

from mediawords.test.db.create import create_test_medium
from mediawords.db import connect_to_db
from mediawords.util.sql import sql_now, get_sql_date_from_epoch

# noinspection PyProtectedMember
from crawler_provider import _add_stale_feeds


def test_add_stale_feeds():
    db = connect_to_db()

    medium = create_test_medium(db, 'foo')

    pending_feeds = []

    feed = {
        'media_id': medium['media_id'],
        'name': 'null last download',
        'url': 'http://null last download',
        'type': 'syndicated',
        'active': True,
        'last_attempted_download_time': None
    }
    feed = db.create('feeds', feed)
    pending_feeds.append(feed)

    feed = {
        'media_id': medium['media_id'],
        'name': 'recent last download',
        'url': 'http://recent last download',
        'type': 'syndicated',
        'active': True,
        'last_attempted_download_time': sql_now()
    }
    db.create('feeds', feed)

    feed = {
        'media_id': medium['media_id'],
        'name': 'recent last new story',
        'url': 'http://recent last new story',
        'type': 'syndicated',
        'active': True,
        'last_attempted_download_time': sql_now(),
        'last_new_story_time': sql_now()
    }
    db.create('feeds', feed)

    feed = {
        'media_id': medium['media_id'],
        'name': '5 minute new story',
        'url': 'http://5 minute new story',
        'type': 'syndicated',
        'active': True,
        'last_attempted_download_time': get_sql_date_from_epoch(int(time.time()) - 300),
        'last_new_story_time': get_sql_date_from_epoch(int(time.time()) - 300),
    }
    feed = db.create('feeds', feed)
    pending_feeds.append(feed)

    feed = {
        'media_id': medium['media_id'],
        'name': 'old last download',
        'url': 'http://old last download',
        'type': 'syndicated',
        'active': True,
        'last_attempted_download_time': get_sql_date_from_epoch(int(time.time()) - (86400 * 10))
    }
    feed = db.create('feeds', feed)
    pending_feeds.append(feed)

    _add_stale_feeds(db)

    num_pending_downloads = db.query("select count(*) from downloads where state = 'pending'").flat()[0]
    assert num_pending_downloads == len(pending_feeds)

    for feed in pending_feeds:
        exists = db.query(
            "select * from downloads where state = 'pending' and feeds_id = %(a)s",
            {'a': feed['feeds_id']}).hash()
        assert exists, "download for feed %s added" % feed['name']
