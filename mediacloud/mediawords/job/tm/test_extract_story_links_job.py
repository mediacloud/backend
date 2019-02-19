"""Test mediawords.tm.extract_story_links."""

import mediawords.test.test_database
import mediawords.job.tm.extract_story_links_job


class TestExtractStoryLinksJobDB(mediawords.test.test_database.TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    def setUp(self) -> None:
        super().setUp()
        db = self.db()

        media = mediawords.test.db.create.create_test_story_stack(db, {'A': {'B': [1]}})

        story = media['A']['feeds']['B']['stories']['1']

        download = mediawords.test.db.create.create_download_for_story(
            db=db,
            feed=media['A']['feeds']['B'],
            story=story,
        )

        mediawords.dbi.downloads.store_content(db, download, '<p>foo</p>')

        self.test_story = story
        self.test_download = download

    def test_extract_links_for_topic_story(self) -> None:
        """Test extract_links_for_topic_story()."""
        db = self.db()

        story = self.test_story

        story['description'] = 'http://foo.com'
        db.update_by_id('stories', story['stories_id'], story)

        topic = mediawords.test.db.create.create_test_topic(db, 'links')
        db.create('topic_stories', {'topics_id': topic['topics_id'], 'stories_id': story['stories_id']})

        mediawords.job.tm.extract_story_links_job.ExtractStoryLinksJob.run_job(story['stories_id'], topic['topics_id'])

        got_topic_links = db.query(
            "select topics_id, stories_id, url from topic_links where topics_id = %(a)s order by url",
            {'a': topic['topics_id']}).hashes()

        expected_topic_links = [
            {'topics_id': topic['topics_id'], 'stories_id': story['stories_id'], 'url': 'http://foo.com'}]

        assert got_topic_links == expected_topic_links

        got_topic_story = db.query(
            "select topics_id, stories_id, link_mined from topic_stories where topics_id =%(a)s and stories_id = %(b)s",
            {'a': topic['topics_id'], 'b': story['stories_id']}).hash()

        expected_topic_story = {'topics_id': topic['topics_id'], 'stories_id': story['stories_id'], 'link_mined': True}

        assert got_topic_story == expected_topic_story
