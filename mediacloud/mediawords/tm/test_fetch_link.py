"""Test mediawords.tm.fetch_link.*"""

import datetime

import mediawords.test.http.hash_server
import mediawords.test.test_database
import mediawords.tm.fetch_link
from mediawords.util.web.user_agent.throttled import McThrottledDomainException


def test_network_is_down() -> None:
    """Test network_is_down()."""
    hs = mediawords.test.http.hash_server.HashServer(port=0, pages={'/foo': 'bar'})
    port = hs.port()
    hs.start()
    assert not mediawords.tm.fetch_link._network_is_down(host='localhost', port=port)

    hs.stop()
    assert mediawords.tm.fetch_link._network_is_down(host='localhost', port=port)


def test_content_matches_topic() -> None:
    """Test content_matches_topic()."""
    assert mediawords.tm.fetch_link.content_matches_topic('foo', {'pattern': 'foo'})
    assert mediawords.tm.fetch_link.content_matches_topic('FOO', {'pattern': 'foo'})
    assert mediawords.tm.fetch_link.content_matches_topic('FOO', {'pattern': ' foo '})
    assert not mediawords.tm.fetch_link.content_matches_topic('foo', {'pattern': 'bar'})
    assert mediawords.tm.fetch_link.content_matches_topic('foo', {'pattern': 'bar'}, assume_match=True)


class TestTMFetchLinkDB(mediawords.test.test_database.TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    def test_fetch_url(self) -> None:
        """Test fetch_url()."""
        db = self.db()

        def _meta_redirect(r):
            return (
                'HTTP/1.0 200 OK\r\n'
                'Content-Type: text/html\r\n\r\n'
                '<meta http-equiv="refresh" content="0; url=%s-foo">\n' % r.url())

        hs = mediawords.test.http.hash_server.HashServer(
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

        # before delyaed start, 404s and 500s should still return None
        assert not mediawords.tm.fetch_link.fetch_url(db, hs.page_url('/404'), **timeout_args).is_success()
        assert not mediawords.tm.fetch_link.fetch_url(db, hs.page_url('/500'), **timeout_args).is_success()

        # request for a valid page should make the call wait until the hs comes up
        assert mediawords.tm.fetch_link.fetch_url(db, hs.page_url('/foo'), **timeout_args).decoded_content() == 'bar'

        # and now a 400 should return a None
        assert not mediawords.tm.fetch_link.fetch_url(db, hs.page_url('/400'), **timeout_args).is_success()

        # make sure invalid url does not raise an exception
        assert not mediawords.tm.fetch_link.fetch_url(db, 'this is not a url', **timeout_args) is None

        # make sure that requests follow meta redirects
        response = mediawords.tm.fetch_link.fetch_url(db, hs.page_url('/mr'), **timeout_args)

        assert response.decoded_content() == 'meta redirect target'
        assert response.request().url() == hs.page_url('/mr-foo')

    def test_fetch_topic_url(self) -> None:
        """Test fetch_topic_url()."""
        db = self.db()

        hs = mediawords.test.http.hash_server.HashServer(
            port=0,
            pages={
                '/foo': '<title>foo</title>',
                '/bar': '<title>bar</title>',
                '/target': '<title>target</title>',
                '/ignore': '<title>ignore</title>',
                '/redirect': {'redirect': '/target'}
            })
        hs.start()

        topic = mediawords.test.db.create_test_topic(db, 'foo')
        topic['pattern'] = '.'
        topic = db.update_by_id('topics', topic['topics_id'], topic)

        before_fetch_date = datetime.datetime.now().isoformat()

        fetch_url = hs.page_url('/foo')

        #  add new story
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': hs.page_url('/foo'),
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING})

        mediawords.tm.fetch_link.fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link.FETCH_STATE_STORY_ADDED
        assert tfu['url'] == fetch_url
        assert tfu['fetch_date'][0:10] == before_fetch_date[0:10]
        assert tfu['code'] == 200
        assert tfu['stories_id'] is not None

        new_story = db.require_by_id('stories', tfu['stories_id'])

        assert new_story['url'] == fetch_url
        assert new_story['title'] == 'foo'

        # bad url
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': fetch_url + '/404',
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING})

        mediawords.tm.fetch_link.fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link.FETCH_STATE_REQUEST_FAILED
        assert tfu['code'] == 404
        assert tfu['message'] == 'Not Found'

        # story match
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': fetch_url,
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING})

        mediawords.tm.fetch_link.fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link.FETCH_STATE_STORY_MATCH
        assert tfu['code'] == 200
        assert tfu['stories_id'] == new_story['stories_id']

        # fail content match
        topic['pattern'] = 'DONTMATCHTHISPATTERN'
        topic = db.update_by_id('topics', topic['topics_id'], topic)

        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': hs.page_url('/bar'),
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING})

        mediawords.tm.fetch_link.fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link.FETCH_STATE_CONTENT_MATCH_FAILED
        assert tfu['code'] == 200

        # domain throttle
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': hs.page_url('/foo'),
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING})

        self.assertRaises(
            McThrottledDomainException,
            mediawords.tm.fetch_link.fetch_topic_url,
            db,
            tfu['topic_fetch_urls_id'])

        # make sure redirected url is used for story
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': hs.page_url('/redirect'),
            'assume_match': True,
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING})

        mediawords.tm.fetch_link.fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link.FETCH_STATE_STORY_ADDED
        assert tfu['code'] == 200
        assert tfu['stories_id'] is not None

        story = db.require_by_id('stories', tfu['stories_id'])

        assert story['url'] == hs.page_url('/target')
        assert story['title'] == 'target'

        # do nothing if state is not pending or requeued
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': hs.page_url('/ignore'),
            'state': mediawords.tm.fetch_link.FETCH_STATE_STORY_MATCH})

        mediawords.tm.fetch_link.fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link.FETCH_STATE_STORY_MATCH
