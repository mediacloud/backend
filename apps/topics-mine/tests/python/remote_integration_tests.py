from mediawords.db import DatabaseHandler
from mediawords.test.db.create import create_test_topic

from topics_mine.fetch_topic_tweets import fetch_topic_tweets

MIN_TEST_TWEET_LENGTH = 10
MIN_TEST_TWITTER_USER_LENGTH = 3


def run_remote_integration_tests(db: DatabaseHandler, source: str, query: str, day: str) -> None:
    """Run sanity test on remote apis."""
    topic = create_test_topic(db, "test_remote_integration")

    tsq = {
        'topics_id': topic['topics_id'],
        'platform': 'twitter',
        'source': source,
        'query': query
    }
    db.create('topic_seed_queries', tsq)

    topic['platform'] = 'twitter'
    topic['pattern'] = '.*'
    topic['start_date'] = day
    topic['end_date'] = day
    db.update_by_id('topics', topic['topics_id'], topic)

    # only fetch 200 tweets to make test quicker
    max_tweets = 200
    fetch_topic_tweets(db, topic['topics_id'], max_tweets)

    # ttd_day = datetime.datetime(year=2016, month=1, day=1)

    # meta_tweets = fetch_meta_tweets(db, topic, ttd_day)
    # ttd = _add_topic_tweet_single_day(db, topic, len(meta_tweets), ttd_day)

    # max_tweets = 100
    # _fetch_tweets_for_day(db, ttd, meta_tweets, max_tweets=max_tweets)

    got_tts = db.query("select * from topic_tweets").hashes()

    # for old ch monitors, lots of the tweets may be deleted
    assert len(got_tts) > max_tweets / 10

    assert len(got_tts[0]['content']) > MIN_TEST_TWEET_LENGTH
    assert len(got_tts[0]['twitter_user']) > MIN_TEST_TWITTER_USER_LENGTH
