from mediawords.db import connect_to_db
from mediawords.test.db.create import (
    create_test_topic,
    create_test_medium,
    create_test_feed,
    create_test_story,
    add_content_to_test_story,
)
from topics_base.stories import add_to_topic_stories, copy_story_to_new_medium


def test_copy_story_to_new_medium_with_download_error():
    """Test copy_story_to_new_medium with an associated download error."""
    db = connect_to_db()

    topic = create_test_topic(db, 'copy foo')

    new_medium = create_test_medium(db, 'copy new')

    old_medium = create_test_medium(db, 'copy old')
    old_feed = create_test_feed(db=db, label='copy old', medium=old_medium)
    old_story = create_test_story(db=db, label='copy old', feed=old_feed)

    add_content_to_test_story(db, old_story, old_feed)

    db.query("update downloads set state = 'error' where stories_id = %(a)s", {'a': old_story['stories_id']})

    add_to_topic_stories(db, old_story, topic)

    new_story = copy_story_to_new_medium(db, topic, old_story, new_medium)

    assert db.find_by_id('stories', new_story['stories_id']) is not None

    new_download = db.query(
        "select * from downloads where stories_id = %(a)s",
        {'a': new_story['stories_id']}).hash()
    assert new_download is not None
    assert new_download['state'] == 'error'
