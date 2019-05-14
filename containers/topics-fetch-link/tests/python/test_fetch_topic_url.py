import datetime

import pytest

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story
from mediawords.test.hash_server import HashServer
from mediawords.util.web.user_agent.throttled import McThrottledDomainException

from topics_base.fetch_states import (
    FETCH_STATE_PENDING,
    FETCH_STATE_STORY_ADDED,
    FETCH_STATE_REQUEST_FAILED,
    FETCH_STATE_IGNORED,
    FETCH_STATE_STORY_MATCH,
    FETCH_STATE_CONTENT_MATCH_FAILED,
)
from topics_fetch_link.fetch_link import fetch_topic_url


def test_fetch_topic_url():
    db = connect_to_db()

    hs = HashServer(
        port=0,
        pages={
            '/foo': '<title>foo</title>',
            '/bar': '<title>bar</title>',
            '/throttle': '<title>throttle</title>',
            '/target': '<title>target</title>',
            '/ignore': '<title>ignore</title>',
            '/redirect': {'redirect': '/target'},
            '/redirect-foo': {'redirect': '/foo'},
        })
    hs.start()

    topic = create_test_topic(db, 'foo')
    topic['pattern'] = '.'
    topic = db.update_by_id('topics', topic['topics_id'], topic)

    medium = create_test_medium(db, 'fetch')
    feed = create_test_feed(db, label='fetch', medium=medium)
    source_story = create_test_story(db, label='source story', feed=feed)
    db.create('topic_stories', {'topics_id': topic['topics_id'], 'stories_id': source_story['stories_id']})

    before_fetch_date = datetime.datetime.now().isoformat()

    fetch_url = hs.page_url('/foo')

    #  add new story
    topic_link = db.create('topic_links', {
        'topics_id': topic['topics_id'],
        'url': fetch_url,
        'stories_id': source_story['stories_id']})

    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': fetch_url,
        'state': FETCH_STATE_PENDING,
        'topic_links_id': topic_link['topic_links_id']})

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_STORY_ADDED
    assert tfu['url'] == fetch_url
    assert tfu['fetch_date'][0:10] == before_fetch_date[0:10]
    assert tfu['code'] == 200
    assert tfu['stories_id'] is not None

    new_story = db.require_by_id('stories', tfu['stories_id'])

    assert new_story['url'] == fetch_url
    assert new_story['title'] == 'foo'

    topic_link = db.require_by_id('topic_links', topic_link['topic_links_id'])

    assert topic_link['ref_stories_id'] == tfu['stories_id']

    # bad url
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': fetch_url + '/404',
        'state': FETCH_STATE_PENDING})

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_REQUEST_FAILED
    assert tfu['code'] == 404
    assert tfu['message'] == 'Not Found'

    # ignore
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': 'http://politicalgraveyard.com',
        'state': FETCH_STATE_PENDING})

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_IGNORED
    assert tfu['code'] == 403

    # story match
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': fetch_url,
        'state': FETCH_STATE_PENDING})

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_STORY_MATCH
    assert tfu['code'] == 200
    assert tfu['stories_id'] == new_story['stories_id']

    # story match for redirected url
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': hs.page_url('/redirect-foo'),
        'state': FETCH_STATE_PENDING})

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_STORY_MATCH
    assert tfu['code'] == 200
    assert tfu['stories_id'] == new_story['stories_id']

    # fail content match
    topic['pattern'] = 'DONTMATCHTHISPATTERN'
    topic = db.update_by_id('topics', topic['topics_id'], topic)

    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': hs.page_url('/bar'),
        'state': FETCH_STATE_PENDING})

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_CONTENT_MATCH_FAILED
    assert tfu['code'] == 200

    # domain throttle
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': hs.page_url('/throttle'),
        'state': FETCH_STATE_PENDING})

    with pytest.raises(McThrottledDomainException):
        fetch_topic_url(db, tfu['topic_fetch_urls_id'])

    # make sure redirected url is used for story
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': hs.page_url('/redirect'),
        'assume_match': True,
        'state': FETCH_STATE_PENDING})

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_STORY_ADDED
    assert tfu['code'] == 200
    assert tfu['stories_id'] is not None

    story = db.require_by_id('stories', tfu['stories_id'])

    assert story['url'] == hs.page_url('/target')
    assert story['title'] == 'target'

    # do nothing if state is not pending or requeued
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': hs.page_url('/ignore'),
        'state': FETCH_STATE_STORY_MATCH})

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_STORY_MATCH

    # try passing some content through the topic_seed_urls table
    tfu = db.create('topic_fetch_urls', {
        'topics_id': topic['topics_id'],
        'url': hs.page_url('/ignore'),
        'assume_match': True,
        'state': FETCH_STATE_PENDING})

    tsu_content = '<title>seeded content</title>'
    db.create('topic_seed_urls', {'topics_id': topic['topics_id'], 'url': tfu['url'], 'content': tsu_content})

    fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

    tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

    assert tfu['state'] == FETCH_STATE_STORY_ADDED
    assert tfu['code'] == 200
    assert tfu['stories_id'] is not None

    story = db.require_by_id('stories', tfu['stories_id'])

    assert story['title'] == 'seeded content'
