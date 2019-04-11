#!/usr/bin/env py.test

from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.dbi.downloads.store import store_content
from mediawords.test.db.create import create_test_medium, create_test_feed, create_download_for_feed, create_test_story


class TestExtractDB(TestCase):
    """Run tests that require database access."""

    __TEST_CONTENT = '<script>ignore</script><p>foo</p>'

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.db = connect_to_db()

        self.test_medium = create_test_medium(self.db, 'downloads test')
        self.test_feed = create_test_feed(self.db, 'downloads test', self.test_medium)
        self.test_download = create_download_for_feed(self.db, self.test_feed)
        self.test_story = create_test_story(self.db, label='downloads est', feed=self.test_feed)

        self.test_download['path'] = 'postgresql:foo'
        self.test_download['state'] = 'success'
        self.test_download['stories_id'] = self.test_story['stories_id']
        self.db.update_by_id('downloads', self.test_download['downloads_id'], self.test_download)

        store_content(db=self.db, download=self.test_download, content=self.__TEST_CONTENT)
