import time

from crawler_provider import run_provider
from mediawords.test.db.create import create_test_medium, create_test_feed
from mediawords.db import connect_to_db


def test_run_provider():
    db = connect_to_db()

    medium = create_test_medium(db, 'foo')
    feed = create_test_feed(db, 'foo', medium=medium)

    hosts = ('foo.bar', 'bar.bat', 'bat.baz')
    downloads_per_host = 3

    for host in hosts:
        for i in range(downloads_per_host):
            download = {
                'feeds_id': feed['feeds_id'],
                'state': 'pending',
                'priority': 1,
                'sequence': 1,
                'type': 'content',
                'url': 'http://' + host + '/' + str(i),
                'host': host}

            db.create('downloads', download)

    run_provider(db, daemon=False)

    # +1 for the test feed
    assert len(hosts) + 1 == db.query("select count(distinct downloads_id) from queued_downloads").flat()[0]

    # make sure that the next loop doesn't just add the same downloads_id values again
    time.sleep(1)
    run_provider(db, daemon=False)

    # +1 for the test feed
    assert 2 * len(hosts) + 1 == db.query("select count(distinct downloads_id) from queued_downloads").flat()[0]
