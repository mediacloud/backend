"""Test mediawords.tm.fetch_link.*"""

import datetime

from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story
from mediawords.test.hash_server import HashServer
from mediawords.test.test_database import TestDatabaseTestCase
from mediawords.util.web.user_agent.throttled import McThrottledDomainException
from mediawords.tm.fetch_link import (
    _fetch_url,
    _get_seeded_content,
    fetch_topic_url,
    _get_failed_url,
    fetch_topic_url_update_state,
)
from mediawords.tm.fetch_states import (
    FETCH_STATE_PENDING,
    FETCH_STATE_REQUEST_FAILED,
    FETCH_STATE_CONTENT_MATCH_FAILED,
    FETCH_STATE_STORY_MATCH,
    FETCH_STATE_STORY_ADDED,
    FETCH_STATE_IGNORED,
    FETCH_STATE_REQUEUED)


class TestTMFetchLinkDB(TestDatabaseTestCase):
    """Run tests that require database access."""

    def test_fetch_url(self) -> None:
        """Test fetch_url()."""
        db = self.db()

        def _meta_redirect(r):
            resp = ""
            resp += 'HTTP/1.0 200 OK\r\n'
            resp += 'Content-Type: text/html\r\n\r\n'
            resp += '<meta http-equiv="refresh" content="0; url=%s-foo">\n' % r.url()
            return resp

        hs = HashServer(
            port=0,
            pages={
                '/foo': 'bar',
                '/400': {'http_status_code': 400},
                '/404': {'http_status_code': 404},
                '/500': {'http_status_code': 500},
                '/mr-foo': 'meta redirect target',
                '/mr': {'callback': _meta_redirect},
            })

        hs.start(delay=2)

        port = hs.port()

        timeout_args = {
            'network_down_host': 'localhost',
            'network_down_port': port,
            'network_down_timeout': 1,
            'domain_timeout': 0
        }

        # before delayed start, 404s and 500s should still return None
        assert not _fetch_url(db, hs.page_url('/404'), **timeout_args).is_success
        assert not _fetch_url(db, hs.page_url('/500'), **timeout_args).is_success

        # request for a valid page should make the call wait until the hs comes up
        assert _fetch_url(db, hs.page_url('/foo'), **timeout_args).content == 'bar'

        # and now a 400 should return a None
        assert not _fetch_url(db, hs.page_url('/400'), **timeout_args).is_success

        # make sure invalid url does not raise an exception
        assert not _fetch_url(db, 'this is not a url', **timeout_args) is None

        # make sure that requests follow meta redirects
        response = _fetch_url(db, hs.page_url('/mr'), **timeout_args)

        assert response.content == 'meta redirect target'
        assert response.last_requested_url == hs.page_url('/mr-foo')

    def test_get_seeded_content(self) -> None:
        """Test get_seeded_content()."""
        db = self.db()

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

    def test_fetch_topic_url(self) -> None:
        """Test fetch_topic_url()."""
        db = self.db()

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

        self.assertRaises(
            McThrottledDomainException,
            fetch_topic_url,
            db,
            tfu['topic_fetch_urls_id'])

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

    def test_get_failed_url(self) -> None:
        """Test get_failed_url()."""
        db = self.db()

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

    def test_fetch_link_job_update_state(self) -> None:
        db = self.db()

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
