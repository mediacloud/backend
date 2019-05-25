# noinspection PyProtectedMember
from mediawords.dbi.downloads.store import _default_amazon_s3_downloads_config, _get_store_for_reading, store_content
from mediawords.util.config.common import DownloadStorageConfig
from .setup_test_downloads import TestDownloadsDB


class TestStoreContent(TestDownloadsDB):
    """Run tests that require database access."""

    def test_store_content(self) -> None:
        """Test store_content by calling store_content and then calling fetch_content() on the postgresql store."""

        amazon_s3_downloads_config = _default_amazon_s3_downloads_config()

        class DoNotReadAllFromS3DownloadStorageConfig(DownloadStorageConfig):
            @staticmethod
            def read_all_from_s3():
                return False

            @staticmethod
            def fallback_postgresql_to_s3():
                return False

            @staticmethod
            def storage_locations():
                return ['postgresql']

        store = _get_store_for_reading(
            download=self.test_download,
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=DoNotReadAllFromS3DownloadStorageConfig(),
        )

        content = 'bat baz bar foo'
        got_download = store_content(db=self.__db, download=self.test_download, content=content)
        got_content = store.fetch_content(db=self.__db, object_id=self.test_download['downloads_id']).decode()

        assert got_content == content
        assert got_download['state'] == 'success'
        assert got_download['path'] == 'postgresql:raw_downloads'
        assert got_download['error_message'] == ''

        content = 'bat baz bar'
        self.test_download['state'] = 'feed_error'
        got_download = store_content(db=self.__db, download=self.test_download, content=content)
        got_content = store.fetch_content(db=self.__db, object_id=self.test_download['downloads_id']).decode()

        assert got_content == content
        assert got_download['state'] == 'feed_error'
        assert got_download['path'] == 'postgresql:raw_downloads'
        assert not got_download['error_message']  # NULL or an empty string
