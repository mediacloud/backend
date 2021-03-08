from mediawords.db import connect_to_db
from mediawords.dbi.stories.stories import add_story
from mediawords.test.db.create import create_test_medium, create_test_feed


def test_add_story_description_unset():
    """Test adding a story without a description being set."""

    db = connect_to_db()

    medium = create_test_medium(db=db, label='test')
    feed = create_test_feed(db=db, label='test', medium=medium)

    story = {
        'url': 'http://test',
        'guid': 'http://test',
        'media_id': medium['media_id'],
        'title': "test",

        # stories.description can be NULL so it's a valid value:
        'description': None,

        'publish_date': '2016-10-15 08:00:00',
        'collect_date': '2016-10-15 10:00:00',
    }

    add_story(db=db, story=story, feeds_id=feed['feeds_id'])

    assert len(db.select(table='stories', what_to_select='*').hashes()) == 1
    assert len(db.select(table='feeds_stories_map', what_to_select='*').hashes()) == 1
