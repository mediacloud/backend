from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from topics_base.stories import create_download_for_new_story


def test_create_download_for_new_story():
    """Test create_download_for_new_story()."""
    db = connect_to_db()

    medium = create_test_medium(db, 'foo')
    feed = create_test_feed(db=db, label='foo', medium=medium)
    story = create_test_story(db=db, label='foo', feed=feed)

    returned_download = create_download_for_new_story(db, story, feed)

    assert returned_download is not None

    got_download = db.query("select * from downloads where stories_id = %(a)s", {'a': story['stories_id']}).hash()

    assert got_download is not None

    assert got_download['downloads_id'] == returned_download['downloads_id']
    assert got_download['feeds_id'] == feed['feeds_id']
    assert got_download['url'] == story['url']
    assert got_download['state'] == 'success'
    assert got_download['type'] == 'content'
    assert not got_download['extracted']
