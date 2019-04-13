from mediawords.dbi.downloads.store import get_content_for_first_download
from mediawords.dbi.downloads.setup_test_downloads import TestDownloadsDB


class TestGetContentForFirstDownload(TestDownloadsDB):
    """Run tests that require database access."""

    def test_get_content_for_first_download(self):
        content = get_content_for_first_download(
            db=self.__db,
            story=self.test_story,
        )
        assert content == self._TEST_CONTENT
