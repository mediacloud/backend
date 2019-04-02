from mediawords.job import JobManager
import mediawords.test.hash_server
import mediawords.test.db.create
import mediawords.test.test_database
import mediawords.tm.fetch_link_states


class TestFetchLinJobkDB(mediawords.test.test_database.TestDatabaseTestCase):
    """Run tests that require database access."""

    def test_fetch_link_job(self) -> None:
        db = self.db()

        hs = mediawords.test.hash_server.HashServer(port=0, pages={
            '/foo': '<title>foo</title>',
            '/throttle': '<title>throttle</title>'})
        hs.start()

        topic = mediawords.test.db.create.create_test_topic(db, 'foo')
        topic['pattern'] = '.'
        topic = db.update_by_id('topics', topic['topics_id'], topic)

        fetch_url = hs.page_url('/foo')

        #  basic sanity test for link fetching
        tfu = db.create('topic_fetch_urls', {
            'topics_id': topic['topics_id'],
            'url': hs.page_url('/foo'),
            'state': mediawords.tm.fetch_link_states.FETCH_STATE_PENDING})

        JobManager.run_remotely(
            name='MediaWords::Job::TM::FetchLink',
            topic_fetch_urls_id=tfu['topic_fetch_urls_id'],
        )

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])

        assert tfu['state'] == mediawords.tm.fetch_link_states.FETCH_STATE_STORY_ADDED
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
            'state': mediawords.tm.fetch_link_states.FETCH_STATE_PENDING})

        JobManager.run_remotely(
            name='MediaWords::Job::TM::FetchLink',
            topic_fetch_urls_id=tfu['topic_fetch_urls_id'],
            dummy_requeue=True,
        )

        tfu = db.require_by_id('topic_fetch_urls', tfu['topic_fetch_urls_id'])
        assert tfu['state'] == mediawords.tm.fetch_link_states.FETCH_STATE_REQUEUED
