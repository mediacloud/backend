from mediawords.job import JobManager
from mediawords.test.db.create import create_test_topic
from mediawords.test.hash_server import HashServer
from mediawords.test.test_database import TestDatabaseTestCase
from mediawords.tm.fetch_states import FETCH_STATE_PENDING, FETCH_STATE_STORY_ADDED, FETCH_STATE_REQUEUED


class TestFetchLinJobDB(TestDatabaseTestCase):
    """Run tests that require database access."""

    def test_fetch_link_job(self) -> None:
        db = self.db()

        hs = HashServer(port=0, pages={
            '/foo': '<title>foo</title>',
            '/throttle': '<title>throttle</title>'})
        hs.start()

        topic = create_test_topic(db, 'foo')
        topic['pattern'] = '.'
        topic = db.update_by_id('topics', topic['topics_id'], topic)

        fetch_url = hs.page_url('/foo')

        #  basic sanity test for link fetching
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': hs.page_url('/foo'),
            'state': FETCH_STATE_PENDING})

        JobManager.run_remotely(
            name='MediaWords::Job::TM::FetchLink',
            topic_fetch_urls_id=tfu['topic_fetch_urls_id'],
        )

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

        JobManager.run_remotely(
            name='MediaWords::Job::TM::FetchLink',
            topic_fetch_urls_id=tfu['topic_fetch_urls_id'],
            dummy_requeue=True,
        )

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])
        assert tfu['state'] == FETCH_STATE_REQUEUED
