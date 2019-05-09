from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.test.db.create import (
    create_test_medium,
    create_test_feed,
    create_test_story,
    create_download_for_story,
)


class TestStoryVectors(TestCase):

    def setUp(self) -> None:
        super().setUp()

        self.db = connect_to_db()

        self.test_medium = create_test_medium(self.db, 'downloads test')
        self.test_feed = create_test_feed(self.db, 'downloads test', self.test_medium)
        self.test_story = create_test_story(self.db, label='downloads est', feed=self.test_feed)
        self.test_download = create_download_for_story(self.db, feed=self.test_feed, story=self.test_story)
