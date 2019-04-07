from mediawords.db.exceptions.handler import McUpdateByIDException
from mediawords.test.db.create import create_test_medium, create_test_story, create_test_feed, create_test_topic
from mediawords.test.testing_database import TestDatabaseTestCase
from mediawords.tm.fetch_link_utils import content_matches_topic, try_update_topic_link_ref_stories_id
from mediawords.tm.fetch_states import FETCH_STATE_STORY_ADDED


def test_content_matches_topic() -> None:
    """Test content_matches_topic()."""
    assert content_matches_topic('foo', {'pattern': 'foo'})
    assert content_matches_topic('FOO', {'pattern': 'foo'})
    assert content_matches_topic('FOO', {'pattern': ' foo '})
    assert not content_matches_topic('foo', {'pattern': 'bar'})
    assert content_matches_topic('foo', {'pattern': 'bar'}, assume_match=True)


class TestTMFetchLinkUtilsDB(TestDatabaseTestCase):

    def test_try_update_topic_link_ref_stories_id(self) -> None:
        """Test try_update_topic_link_ref_stories_id()."""
        db = self.db()

        medium = create_test_medium(db, 'foo')
        feed = create_test_feed(db, label='foo', medium=medium)
        source_story = create_test_story(db, label='source story', feed=feed)
        target_story = create_test_story(db, label='target story a', feed=feed)

        topic = create_test_topic(db, 'foo')

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
            'state': FETCH_STATE_STORY_ADDED,
            'stories_id': target_story['stories_id']})

        try_update_topic_link_ref_stories_id(db, topic_fetch_url_a)

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
            'state': FETCH_STATE_STORY_ADDED,
            'stories_id': target_story['stories_id']})

        try_update_topic_link_ref_stories_id(db, topic_fetch_url_b)

        topic_link_b = db.require_by_id('topic_links', topic_link_b['topic_links_id'])

        assert topic_link_b['ref_stories_id'] is None

        # now generate an non-unique error and make sure we get an error
        bogus_tfu = {'topic_links_id': 0, 'topics_id': 'nan', 'stories_id': 'nan'}
        with self.assertRaises(McUpdateByIDException):
            try_update_topic_link_ref_stories_id(db, bogus_tfu)
