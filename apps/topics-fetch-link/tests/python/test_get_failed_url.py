from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic
# noinspection PyProtectedMember
from topics_base.fetch_states import (
    FETCH_STATE_STORY_ADDED,
    FETCH_STATE_STORY_MATCH,
    FETCH_STATE_REQUEST_FAILED,
    FETCH_STATE_CONTENT_MATCH_FAILED,
)
from topics_fetch_link.fetch_link import _get_failed_url


def test_get_failed_url():
    db = connect_to_db()

    topic = create_test_topic(db, 'foo')
    topics_id = topic['topics_id']

    tfus = [
        ['http://story.added', FETCH_STATE_STORY_ADDED],
        ['http://story.matched', FETCH_STATE_STORY_MATCH],
        ['http://request.failed', FETCH_STATE_REQUEST_FAILED],
        ['http://content.match.failed', FETCH_STATE_CONTENT_MATCH_FAILED]
    ]

    for tfu in tfus:
        db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': tfu[0],
            'state': tfu[1]})

    request_failed_tfu = _get_failed_url(db, topics_id, 'http://request.failed')
    assert request_failed_tfu is not None
    assert request_failed_tfu['url'] == 'http://request.failed'

    content_failed_tfu = _get_failed_url(db, topics_id, 'http://content.match.failed')
    assert content_failed_tfu is not None
    assert content_failed_tfu['url'] == 'http://content.match.failed'

    assert _get_failed_url(db, topics_id, 'http://story,added') is None
    assert _get_failed_url(db, topics_id, 'http://bogus.url') is None
    assert _get_failed_url(db, 0, 'http://request.failed') is None
