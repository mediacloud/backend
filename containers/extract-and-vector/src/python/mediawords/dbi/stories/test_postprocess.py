from mediawords.dbi.stories.postprocess import mark_as_processed
from mediawords.test.db.create import create_test_medium, create_test_feed, create_test_story
from mediawords.test.test_database import TestDatabaseTestCase


class TestPostprocess(TestDatabaseTestCase):
    TEST_MEDIUM_NAME = 'test medium'
    TEST_FEED_NAME = 'test feed'
    TEST_STORY_NAME = 'test story'

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.test_medium = create_test_medium(self.db(), self.TEST_MEDIUM_NAME)
        self.test_feed = create_test_feed(self.db(), self.TEST_FEED_NAME, self.test_medium)
        self.test_story = create_test_story(self.db(), label=self.TEST_STORY_NAME, feed=self.test_feed)

    def test_mark_as_processed(self):
        processed_stories = self.db().query("SELECT * FROM processed_stories").hashes()
        assert len(processed_stories) == 0

        mark_as_processed(db=self.db(), stories_id=self.test_story['stories_id'])

        processed_stories = self.db().query("SELECT * FROM processed_stories").hashes()
        assert len(processed_stories) == 1
        assert processed_stories[0]['stories_id'] == self.test_story['stories_id']
