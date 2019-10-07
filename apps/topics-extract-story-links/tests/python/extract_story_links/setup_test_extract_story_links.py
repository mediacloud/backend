from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import store_content
from mediawords.test.db.create import create_test_story_stack, create_download_for_story


class TestExtractStoryLinksDB(TestCase):
    """Run tests that require database access."""

    def setUp(self):
        """Create test_story and test_download."""
        super().setUp()
        self.db = connect_to_db()

        media = create_test_story_stack(self.db, {'A': {'B': [1]}})

        story = media['A']['feeds']['B']['stories']['1']

        download = create_download_for_story(
            db=self.db,
            feed=media['A']['feeds']['B'],
            story=story,
        )

        store_content(self.db, download, '<p>foo</p>')

        self.test_story = story
        self.test_download = download
