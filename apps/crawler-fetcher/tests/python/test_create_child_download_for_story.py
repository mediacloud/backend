# noinspection PyProtectedMember
from crawler_fetcher.new_story import _create_child_download_for_story

from .setup_test_stories import TestStories


class TestCreateChildDownloadForStory(TestStories):

    def test_create_child_download_for_story(self):
        downloads = self.db.query('SELECT * FROM downloads').hashes()
        assert len(downloads) == 1

        _create_child_download_for_story(
            db=self.db,
            story=self.test_story,
            parent_download=self.test_download,
        )

        downloads = self.db.query('SELECT * FROM downloads').hashes()
        assert len(downloads) == 2

        child_download = self.db.query("""
            SELECT *
            FROM downloads
            WHERE parent = %(parent_downloads_id)s
          """, {'parent_downloads_id': self.test_download['downloads_id']}).hash()
        assert child_download

        assert child_download['feeds_id'] == self.test_feed['feeds_id']
        assert child_download['stories_id'] == self.test_story['stories_id']
