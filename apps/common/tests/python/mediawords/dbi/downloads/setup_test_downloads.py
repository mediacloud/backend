from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import store_content
from mediawords.test.db.create import create_test_medium, create_test_feed, create_download_for_feed, create_test_story


class TestDownloadsDB(TestCase):
    """Run tests that require database access."""

    __slots__ = [
        '__db',
    ]

    _TEST_CONTENT = '<script>ignore</script><p>foo</p>'

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.__db = connect_to_db()

        self.test_medium = create_test_medium(self.__db, 'downloads test')
        self.test_feed = create_test_feed(self.__db, 'downloads test', self.test_medium)
        self.test_download = create_download_for_feed(self.__db, self.test_feed)
        self.test_story = create_test_story(self.__db, label='downloads est', feed=self.test_feed)

        self.test_download['path'] = 'postgresql:foo'
        self.test_download['state'] = 'success'
        self.test_download['stories_id'] = self.test_story['stories_id']
        self.__db.update_by_id('downloads', self.test_download['downloads_id'], self.test_download)

        store_content(db=self.__db, download=self.test_download, content=self._TEST_CONTENT)
