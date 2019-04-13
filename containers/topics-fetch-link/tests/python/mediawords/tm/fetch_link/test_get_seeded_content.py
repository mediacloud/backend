from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic
# noinspection PyProtectedMember
from mediawords.tm.fetch_link import _get_seeded_content, fetch_topic_url
from mediawords.tm.fetch_states import FETCH_STATE_PENDING, FETCH_STATE_STORY_ADDED


def test_get_seeded_content():
    db = connect_to_db()

    topic = create_test_topic(db, 'foo')
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': 'http://0.0.0.1/foo',
        'assume_match': True,
        'state': FETCH_STATE_PENDING})

    assert _get_seeded_content(db, tfu) is None

    tsu_content = '<title>seeded content</title>'
    db.create('topic_seed_urls', {'topics_id': topic['topics_id'], 'url': tfu['url'], 'content': tsu_content})

    response = _get_seeded_content(db, tfu)

    assert response.content == tsu_content
    assert response.code == 200
    assert response.last_requested_url == tfu['url']

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_STORY_ADDED
    assert tfu['code'] == 200
    assert tfu['stories_id'] is not None

    story = db.require_by_id('stories', tfu['stories_id'])

    assert story['title'] == 'seeded content'
