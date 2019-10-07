from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic
from topics_base.fetch_states import FETCH_STATE_PYTHON_ERROR
# noinspection PyProtectedMember
from topics_fetch_twitter_urls.fetch_twitter_urls import URLS_CHUNK_SIZE, _call_function_on_url_chunks


def test_call_function_on_url_chunk():
    """test _call_function_on_url_chunk."""
    _chunk_collector = []

    # noinspection PyUnusedLocal
    def _test_function(db_, topic_, urls_):
        _chunk_collector.append(urls_)

    # noinspection PyUnusedLocal
    def _error_function(db_, topic_, urls_):
        raise Exception('chunk exception')

    db = connect_to_db()
    topic = create_test_topic(db, 'test')

    urls = list(range(URLS_CHUNK_SIZE * 2))

    _call_function_on_url_chunks(db, topic, urls, _test_function)

    assert _chunk_collector == [urls[0:URLS_CHUNK_SIZE], urls[URLS_CHUNK_SIZE:]]

    for i in range(URLS_CHUNK_SIZE * 2):
        db.create('topic_fetch_urls', {'topics_id': topic['topics_id'], 'url': 'foo', 'state': 'pending'})

    topic_fetch_urls = db.query("select * from topic_fetch_urls").hashes()

    _call_function_on_url_chunks(db, topic, topic_fetch_urls, _error_function)

    [error_count] = db.query(
        "select count(*) from topic_fetch_urls where state = %(a)s",
        {'a': FETCH_STATE_PYTHON_ERROR}).flat()

    assert error_count == URLS_CHUNK_SIZE * 2
