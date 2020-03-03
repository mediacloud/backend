from mediawords.db import DatabaseHandler
from mediawords.test.db.create import create_test_topic
from topics_mine.fetch_topic_posts import fetch_topic_posts

# arbitrary tests for tweets / users so that we don't have to use fixtures
MIN_TEST_POST_LENGTH = 10
MIN_TEST_AUTHOR_LENGTH = 3


def validate_remote_integration(db: DatabaseHandler, source: str, query: str, day: str) -> None:
    """Run sanity test on remote APIs."""

    topic = create_test_topic(db, "test_remote_integration")

    tsq = {
        'topics_id': topic['topics_id'],
        'platform': 'twitter',
        'source': source,
        'query': query
    }
    tsq = db.create('topic_seed_queries', tsq)

    topic['platform'] = 'twitter'
    topic['pattern'] = '.*'
    topic['start_date'] = day
    topic['end_date'] = day
    topic['mode'] = 'url_sharing'
    db.update_by_id('topics', topic['topics_id'], topic)

    fetch_topic_posts(db, tsq)

    got_tts = db.query("select * from topic_posts").hashes()

    # for old ch monitors, lots of the posts may be deleted
    assert len(got_tts) > 20

    assert len(got_tts[0]['content']) > MIN_TEST_POST_LENGTH
    assert len(got_tts[0]['author']) > MIN_TEST_AUTHOR_LENGTH
