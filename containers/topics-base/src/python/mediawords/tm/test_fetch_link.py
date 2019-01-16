"""Test mediawords.tm.fetch_link.*"""

import datetime

import mediawords.test.db.create
import mediawords.test.hash_server
import mediawords.test.test_database
import mediawords.tm.fetch_link
from mediawords.db.exceptions.handler import McUpdateByIDException
from mediawords.util.web.user_agent.throttled import McThrottledDomainException


def testcontent_matches_topic() -> None:
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
            resp = ""
            resp += 'HTTP/1.0 200 OK\r\n'
            resp += 'Content-Type: text/html\r\n\r\n'
            resp += '<meta http-equiv="refresh" content="0; url=%s-foo">\n' % r.url()
            return resp

        hs = mediawords.test.hash_server.HashServer(
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
        assert not mediawords.tm.fetch_link._fetch_url(db, hs.page_url('/404'), **timeout_args).is_success
        assert not mediawords.tm.fetch_link._fetch_url(db, hs.page_url('/500'), **timeout_args).is_success

        # request for a valid page should make the call wait until the hs comes up
        assert mediawords.tm.fetch_link._fetch_url(db, hs.page_url('/foo'), **timeout_args).content == 'bar'

        # and now a 400 should return a None
        assert not mediawords.tm.fetch_link._fetch_url(db, hs.page_url('/400'), **timeout_args).is_success

        # make sure invalid url does not raise an exception
        assert not mediawords.tm.fetch_link._fetch_url(db, 'this is not a url', **timeout_args) is None

        # make sure that requests follow meta redirects
        response = mediawords.tm.fetch_link._fetch_url(db, hs.page_url('/mr'), **timeout_args)

        assert response.content == 'meta redirect target'
        assert response.last_requested_url == hs.page_url('/mr-foo')

    def test_get_seeded_content(self) -> None:
        """Test get_seeded_content()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'foo')
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': 'http://0.0.0.1/foo',
            'assume_match': True,
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING})

        assert mediawords.tm.fetch_link._get_seeded_content(db, tfu) is None

        tsu_content = '<title>seeded content</title>'
        db.create('topic_seed_urls', {'topics_id': topic['topics_id'], 'url': tfu['url'], 'content': tsu_content})

        response = mediawords.tm.fetch_link._get_seeded_content(db, tfu)

        assert response.content == tsu_content
        assert response.code == 200
        assert response.last_requested_url == tfu['url']

        mediawords.tm.fetch_link.fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link.FETCH_STATE_STORY_ADDED
        assert tfu['code'] == 200
        assert tfu['stories_id'] is not None

        story = db.require_by_id('stories', tfu['stories_id'])

        assert story['title'] == 'seeded content'

    def test_fetch_topic_url(self) -> None:
        """Test fetch_topic_url()."""
        db = self.db()

        hs = mediawords.test.hash_server.HashServer(
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

        topic = mediawords.test.db.create.create_test_topic(db, 'foo')
        topic['pattern'] = '.'
        topic = db.update_by_id('topics', topic['topics_id'], topic)

        medium = mediawords.test.db.create.create_test_medium(db, 'fetch')
        feed = mediawords.test.db.create.create_test_feed(db, label='fetch', medium=medium)
        source_story = mediawords.test.db.create.create_test_story(db, label='source story', feed=feed)
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
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING,
            'topic_links_id': topic_link['topic_links_id']})

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

        topic_link = db.require_by_id('topic_links', topic_link['topic_links_id'])

        assert topic_link['ref_stories_id'] == tfu['stories_id']

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

        # ignore
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': 'http://politicalgraveyard.com',
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING})

        mediawords.tm.fetch_link.fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link.FETCH_STATE_IGNORED
        assert tfu['code'] == 403

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

        # story match for redirected url
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': hs.page_url('/redirect-foo'),
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
            'url': hs.page_url('/throttle'),
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

        # try passing some content through the topic_seed_urls table
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': hs.page_url('/ignore'),
            'assume_match': True,
            'state': mediawords.tm.fetch_link.FETCH_STATE_PENDING})

        tsu_content = '<title>seeded content</title>'
        db.create('topic_seed_urls', {'topics_id': topic['topics_id'], 'url': tfu['url'], 'content': tsu_content})

        mediawords.tm.fetch_link.fetch_topic_url(db, tfu['topic_fetch_urls_id'], domain_timeout=0)

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link.FETCH_STATE_STORY_ADDED
        assert tfu['code'] == 200
        assert tfu['stories_id'] is not None

        story = db.require_by_id('stories', tfu['stories_id'])

        assert story['title'] == 'seeded content'

    def test_get_failed_url(self) -> None:
        """Test get_failed_url()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'foo')
        topics_id = topic['topics_id']

        tfus = [
            ['http://story.added', mediawords.tm.fetch_link.FETCH_STATE_STORY_ADDED],
            ['http://story.matched', mediawords.tm.fetch_link.FETCH_STATE_STORY_MATCH],
            ['http://request.failed', mediawords.tm.fetch_link.FETCH_STATE_REQUEST_FAILED],
            ['http://content.match.failed', mediawords.tm.fetch_link.FETCH_STATE_CONTENT_MATCH_FAILED]
        ]

        for tfu in tfus:
            db.create('topic_fetch_urls', {
                'topics_id': topic['topics_id'],
                'url': tfu[0],
                'state': tfu[1]})

        request_failed_tfu = mediawords.tm.fetch_link._get_failed_url(db, topics_id, 'http://request.failed')
        assert request_failed_tfu is not None
        assert request_failed_tfu['url'] == 'http://request.failed'

        content_failed_tfu = mediawords.tm.fetch_link._get_failed_url(db, topics_id, 'http://content.match.failed')
        assert content_failed_tfu is not None
        assert content_failed_tfu['url'] == 'http://content.match.failed'

        assert mediawords.tm.fetch_link._get_failed_url(db, topics_id, 'http://story,added') is None
        assert mediawords.tm.fetch_link._get_failed_url(db, topics_id, 'http://bogus.url') is None
        assert mediawords.tm.fetch_link._get_failed_url(db, 0, 'http://request.failed') is None

    def test_try_update_topic_link_ref_stories_id(self) -> None:
        """Test try_update_topic_link_ref_stories_id()."""
        db = self.db()

        medium = mediawords.test.db.create.create_test_medium(db, 'foo')
        feed = mediawords.test.db.create.create_test_feed(db, label='foo', medium=medium)
        source_story = mediawords.test.db.create.create_test_story(db, label='source story', feed=feed)
        target_story = mediawords.test.db.create.create_test_story(db, label='target story a', feed=feed)

        topic = mediawords.test.db.create.create_test_topic(db, 'foo')

        db.create('topic_stories', {
            'topics_id': topic['topics_id'],
            'stories_id': source_story['stories_id']})

        # first update should work
        topic_link_a = db.create('topic_links', {
            'topics_id': topic['topics_id'],
            'stories_id': source_story['stories_id'],
            'url': 'http://foo.com'})

        topic_fetch_url_a = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': 'http://foo.com',
            'topic_links_id': topic_link_a['topic_links_id'],
            'state': mediawords.tm.fetch_link.FETCH_STATE_STORY_ADDED,
            'stories_id': target_story['stories_id']})

        mediawords.tm.fetch_link.try_update_topic_link_ref_stories_id(db, topic_fetch_url_a)

        topic_link_a = db.require_by_id('topic_links', topic_link_a['topic_links_id'])

        assert topic_link_a['ref_stories_id'] == target_story['stories_id']

        # second one should silently fail
        topic_link_b = db.create('topic_links', {
            'topics_id': topic['topics_id'],
            'stories_id': source_story['stories_id'],
            'url': 'http://foo.com'})

        topic_fetch_url_b = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': 'http://foo.com',
            'topic_links_id': topic_link_a['topic_links_id'],
            'state': mediawords.tm.fetch_link.FETCH_STATE_STORY_ADDED,
            'stories_id': target_story['stories_id']})

        mediawords.tm.fetch_link.try_update_topic_link_ref_stories_id(db, topic_fetch_url_b)

        topic_link_b = db.require_by_id('topic_links', topic_link_b['topic_links_id'])

        assert topic_link_b['ref_stories_id'] is None

        # now generate an non-unique error and make sure we get an error
        bogus_tfu = {'topic_links_id': 0, 'topics_id': 'nan', 'stories_id': 'nan'}
        with self.assertRaises(McUpdateByIDException):
            mediawords.tm.fetch_link.try_update_topic_link_ref_stories_id(db, bogus_tfu)
