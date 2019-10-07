from mediawords.db import connect_to_db
from mediawords.dbi.stories.postprocess import mark_as_processed
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story

TEST_MEDIUM_NAME = 'test medium'
TEST_FEED_NAME = 'test feed'
TEST_STORY_NAME = 'test story'


def test_mark_as_processed():
    db = connect_to_db()

    test_medium = create_test_medium(db=db, label=TEST_MEDIUM_NAME)
    test_feed = create_test_feed(db=db, label=TEST_FEED_NAME, medium=test_medium)
    test_story = create_test_story(db=db, label=TEST_STORY_NAME, feed=test_feed)

    processed_stories = db.query("SELECT * FROM processed_stories").hashes()
    assert len(processed_stories) == 0

    mark_as_processed(db=db, stories_id=test_story['stories_id'])

    processed_stories = db.query("SELECT * FROM processed_stories").hashes()
    assert len(processed_stories) == 1
    assert processed_stories[0]['stories_id'] == test_story['stories_id']
