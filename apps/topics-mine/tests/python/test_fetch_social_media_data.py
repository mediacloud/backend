import mediawords.db
from mediawords.test.db.create import create_test_topic, create_test_topic_stories
from topics_mine.mine import fetch_social_media_data

from mediawords.util.log import create_logger
log = create_logger(__name__)

def test_fetch_social_media_data():
    db = mediawords.db.connect_to_db()

    num_stories = 20

    topic = create_test_topic(db, 'foo')
    create_test_topic_stories(db, topic, 1, num_stories)

    db.query("update stories set url = stories_id::text")

    fetch_social_media_data(db, topic)

    num_fetched_stories = db.query(
        "select count(*) from story_statistics where facebook_api_error like '%URL is not HTTP%'").flat()[0]

    log.warning(db.query("select facebook_api_error from story_statistics").flat())

    assert num_fetched_stories == num_stories
