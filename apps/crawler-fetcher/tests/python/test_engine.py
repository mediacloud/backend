from crawler_fetcher.engine import run_fetcher
from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from mediawords.test.hash_server import HashServer
from mediawords.util.network import random_unused_port


def test_run_fetcher():
    db = connect_to_db()

    medium = create_test_medium(db=db, label='foo')
    feed = create_test_feed(db=db, label='foo', medium=medium)
    story = create_test_story(db=db, label='foo', feed=feed)

    port = random_unused_port()
    pages = {
        '/foo': 'foo',
        '/bar': 'bar',
    }

    hs = HashServer(port=port, pages=pages)
    hs.start()

    download = db.create(table='downloads', insert_hash={
        'state': 'pending',
        'feeds_id': feed['feeds_id'],
        'stories_id': story['stories_id'],
        'type': 'content',
        'sequence': 1,
        'priority': 1,
        'url': f"http://localhost:{port}/foo",
        'host': 'localhost',
    })

    db.query("""
        INSERT INTO queued_downloads (downloads_id)
        SELECT downloads_id FROM downloads
    """)

    run_fetcher(no_daemon=True)

    test_download = db.find_by_id(table='downloads', object_id=download['downloads_id'])
    assert test_download['state'] == 'success'
