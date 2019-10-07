from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed
from crawler_provider import provide_download_ids


def test_provide_download_ids() -> None:
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

    download_ids = provide_download_ids(db)

    # +1 for the test feed
    assert len(download_ids) == len(hosts) + 1
