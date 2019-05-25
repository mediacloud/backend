# noinspection PyProtectedMember
from mediawords.dbi.downloads.store import (
    McDBIDownloadsException,
    fetch_content,
    _default_amazon_s3_downloads_config,
    _get_store_for_reading,
)
from .setup_test_downloads import TestDownloadsDB
from mediawords.util.config.common import DownloadStorageConfig


class TestFetchContent(TestDownloadsDB):
    """Run tests that require database access."""

    def test_fetch_content(self) -> None:
        """Test fetch_content by manually storing using the PostgreSQL store and then trying to fetch it."""
        db = self.__db
        with self.assertRaises(McDBIDownloadsException):
            fetch_content(db=db, download={})

        with self.assertRaises(McDBIDownloadsException):
            fetch_content(db=db, download={'downloads_id': 1, 'state': 'error'})

        amazon_s3_downloads_config = _default_amazon_s3_downloads_config()

        class DoNotReadAllFromS3DownloadStorageConfig(DownloadStorageConfig):
            @staticmethod
            def read_all_from_s3():
                return False

            @staticmethod
            def fallback_postgresql_to_s3():
                return False

        store = _get_store_for_reading(
            download=self.test_download,
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=DoNotReadAllFromS3DownloadStorageConfig(),
        )

        content = 'foo bar'
        store.store_content(db=db, object_id=self.test_download['downloads_id'], content=content)
        got_content = fetch_content(
            db=db,
            download=self.test_download,
            download_storage_config=DoNotReadAllFromS3DownloadStorageConfig(),
        )
        assert got_content == content

        content = b'foo bar'
        store.store_content(db=db, object_id=self.test_download['downloads_id'], content=content)
        got_content = fetch_content(
            db=db,
            download=self.test_download,
            download_storage_config=DoNotReadAllFromS3DownloadStorageConfig(),
        )
        assert got_content == content.decode()
