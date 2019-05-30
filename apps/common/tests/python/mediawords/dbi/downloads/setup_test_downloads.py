from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import store_content
from mediawords.test.db.create import (
    create_test_medium,
    create_test_feed,
    create_download_for_feed,
    create_test_story,
    create_download_for_story,
)


class TestDownloadsDB(TestCase):
    """Run tests that require database access."""

    __slots__ = [
        '_db',
    ]

    _TEST_CONTENT = '<script>ignore</script><p>foo</p>'

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self._db = connect_to_db()

        self.test_medium = create_test_medium(self._db, 'downloads test')
        self.test_feed = create_test_feed(self._db, 'downloads test', self.test_medium)
        self.test_download_feed = create_download_for_feed(self._db, self.test_feed)
        self.test_story = create_test_story(self._db, label='downloads est', feed=self.test_feed)
        self.test_download = create_download_for_story(self._db, feed=self.test_feed, story=self.test_story)

        store_content(db=self._db, download=self.test_download, content=self._TEST_CONTENT)
