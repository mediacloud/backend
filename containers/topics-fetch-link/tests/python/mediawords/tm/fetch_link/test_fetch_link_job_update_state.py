from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic
from mediawords.test.hash_server import HashServer
from mediawords.tm.fetch_link import fetch_topic_url_update_state
from mediawords.tm.fetch_states import FETCH_STATE_PENDING, FETCH_STATE_STORY_ADDED, FETCH_STATE_REQUEUED


def test_fetch_link_job_update_state():
    db = connect_to_db()

    hs = HashServer(port=0, pages={
        '/foo': '<title>foo</title>',
        '/throttle': '<title>throttle</title>'})
    hs.start()

    topic = create_test_topic(db, 'foo')
    topic['pattern'] = '.'
    topic = db.update_by_id('topics', topic['topics_id'], topic)

    fetch_url = hs.page_url('/foo')

    # basic sanity test for link fetching
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': hs.page_url('/foo'),
        'state': FETCH_STATE_PENDING})

    fetch_topic_url_update_state(db=db, topic_fetch_urls_id=tfu['topic_fetch_urls_id'])

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_STORY_ADDED
    assert tfu['url'] == fetch_url
    assert tfu['code'] == 200
    assert tfu['stories_id'] is not None

    new_story = db.require_by_id('stories', tfu['stories_id'])

    assert new_story['url'] == fetch_url
    assert new_story['title'] == 'foo'

    # now make sure that the domain throttling sets
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': hs.page_url('/throttle'),
        'state': FETCH_STATE_PENDING})

    fetch_topic_url_update_state(db=db, topic_fetch_urls_id=tfu['topic_fetch_urls_id'])

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])
    assert tfu['state'] == FETCH_STATE_REQUEUED
