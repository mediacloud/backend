from mediawords.test.db import create_test_medium, create_test_feed, create_download_for_feed, create_test_story
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase


class TestProcess(TestDatabaseWithSchemaTestCase):
    TEST_MEDIUM_NAME = 'test medium'
    TEST_FEED_NAME = 'test feed'
    TEST_STORY_NAME = 'test story'

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.test_medium = create_test_medium(self.db(), self.TEST_MEDIUM_NAME)
        self.test_feed = create_test_feed(self.db(), self.TEST_FEED_NAME, self.test_medium)
        self.test_download = create_download_for_feed(self.db(), self.test_feed)
        self.test_story = create_test_story(self.db(), label=self.TEST_STORY_NAME, feed=self.test_feed)

        self.test_download['path'] = 'postgresql:foo'
        self.test_download['state'] = 'success'
        self.test_download['stories_id'] = self.test_story['stories_id']
        self.db().update_by_id('downloads', self.test_download['downloads_id'], self.test_download)
