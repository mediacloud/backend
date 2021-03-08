from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.test.db.create import (
    create_test_medium,
    create_test_feed,
    create_test_story,
    create_download_for_story,
)


class TestStories(TestCase):
    TEST_MEDIUM_NAME = 'test medium'
    TEST_FEED_NAME = 'test feed'
    TEST_STORY_NAME = 'test story'

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.db = connect_to_db()

        self.test_medium = create_test_medium(self.db, self.TEST_MEDIUM_NAME)
        self.test_feed = create_test_feed(self.db, self.TEST_FEED_NAME, self.test_medium)
        self.test_story = create_test_story(self.db, label=self.TEST_STORY_NAME, feed=self.test_feed)
        self.test_download = create_download_for_story(self.db, feed=self.test_feed, story=self.test_story)
