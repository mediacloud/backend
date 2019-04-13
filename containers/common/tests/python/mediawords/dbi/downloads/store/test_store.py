"""Test mediawords.dbi.downloads.store."""

from unittest import TestCase

# noinspection PyProtectedMember
from mediawords.dbi.downloads.store import (
    _default_amazon_s3_downloads_config,
    _default_download_storage_config,
    _get_inline_store,
    _get_amazon_s3_store,
    _get_postgresql_store,
    _get_store_for_writing,
    _get_store_for_reading,
    McDBIDownloadsException,
)
from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.key_value_store.cached_amazon_s3 import CachedAmazonS3Store
from mediawords.key_value_store.database_inline import DatabaseInlineStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.key_value_store.multiple_stores import MultipleStoresStore
from mediawords.test.text import TestCaseTextUtilities
from mediawords.util.config.common import DownloadStorageConfig
from mediawords.util.log import create_logger

log = create_logger(__name__)


class TestDownloadsStore(TestCase, TestCaseTextUtilities):
    """Test case for downloads tests."""

    def test_get_inline_store(self) -> None:
        """Test _get_inline_store."""
        store = _get_inline_store()

        assert isinstance(store, DatabaseInlineStore)

        # make sure the store is a singleton
        assert store is _get_inline_store()

    def test_get_amazon_s3_store(self) -> None:
        """Test _get_amazon_s3_store."""

        amazon_s3_downloads_config = _default_amazon_s3_downloads_config()

        class DoNotCacheS3DownloadStoreConfig(DownloadStorageConfig):
            @staticmethod
            def cache_s3():
                return False

        store = _get_amazon_s3_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=DoNotCacheS3DownloadStoreConfig(),
        )
        assert isinstance(store, AmazonS3Store)
        assert store is _get_amazon_s3_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=DoNotCacheS3DownloadStoreConfig(),
        )

        class CacheS3DownloadStoreConfig(DownloadStorageConfig):
            @staticmethod
            def cache_s3():
                return True

        store = _get_amazon_s3_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=CacheS3DownloadStoreConfig(),
        )
        assert isinstance(store, CachedAmazonS3Store)
        assert store is _get_amazon_s3_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=CacheS3DownloadStoreConfig(),
        )

    def test_get_postgresql_store(self) -> None:
        """Test _get_postgresql_store."""

        amazon_s3_downloads_config = _default_amazon_s3_downloads_config()

        class DoNotFallbackToS3DownloadStorageConfig(DownloadStorageConfig):
            @staticmethod
            def fallback_postgresql_to_s3():
                return False

        store = _get_postgresql_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=DoNotFallbackToS3DownloadStorageConfig(),
        )
        assert isinstance(store, PostgreSQLStore)
        assert store is _get_postgresql_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=DoNotFallbackToS3DownloadStorageConfig(),
        )

        class FallbackToS3DownloadStorageConfig(DownloadStorageConfig):
            @staticmethod
            def fallback_postgresql_to_s3():
                return True

        store = _get_postgresql_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=FallbackToS3DownloadStorageConfig(),
        )
        assert isinstance(store, MultipleStoresStore)
        assert store is _get_postgresql_store(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=FallbackToS3DownloadStorageConfig(),
        )

    def test_get_store_for_writing(self) -> None:
        """Test _get_store_for_writing."""

        amazon_s3_downloads_config = _default_amazon_s3_downloads_config()

        class NoLocationsDownloadStorageConfig(DownloadStorageConfig):
            @staticmethod
            def storage_locations():
                return []

        with self.assertRaises(McDBIDownloadsException):
            _get_store_for_writing(
                amazon_s3_downloads_config=amazon_s3_downloads_config,
                download_storage_config=NoLocationsDownloadStorageConfig(),
            )

        class InvalidLocationDownloadStorageConfig(DownloadStorageConfig):
            @staticmethod
            def storage_locations():
                return [
                    's3',
                    'postgresql',
                    'databaseinline',  # invalid?
                ]

        with self.assertRaises(McDBIDownloadsException):
            _get_store_for_writing(
                amazon_s3_downloads_config=amazon_s3_downloads_config,
                download_storage_config=InvalidLocationDownloadStorageConfig(),
            )

        class ValidLocationDownloadStorageConfig(DownloadStorageConfig):
            @staticmethod
            def storage_locations():
                return [
                    's3',
                    'postgresql',
                ]

        store = _get_store_for_writing(
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=ValidLocationDownloadStorageConfig(),
        )

        assert isinstance(store, MultipleStoresStore)

        stores = store.stores_for_writing()

        assert len(stores) == 2
        assert isinstance(stores[0], AmazonS3Store)
        assert isinstance(stores[1], PostgreSQLStore)

    def test_get_store_for_reading(self) -> None:
        """Test _get_store_for_reading."""

        amazon_s3_downloads_config = _default_amazon_s3_downloads_config()

        class ReadAllFromS3DownloadStorageConfig(DownloadStorageConfig):
            @staticmethod
            def read_all_from_s3():
                return True

        store = _get_store_for_reading(
            download={'path': 'foo:'},
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=ReadAllFromS3DownloadStorageConfig(),
        )
        assert isinstance(store, AmazonS3Store)

        store = _get_store_for_reading(
            download={'path': 'postgresql:'},
            amazon_s3_downloads_config=amazon_s3_downloads_config,
            download_storage_config=ReadAllFromS3DownloadStorageConfig(),
        )
        assert isinstance(store, AmazonS3Store)

        class DoNotReadAllFromS3DownloadStorageConfig(DownloadStorageConfig):
            @staticmethod
            def read_all_from_s3():
                return False

            @staticmethod
            def fallback_postgresql_to_s3():
                return False

        path_lookup = {
            'content': DatabaseInlineStore,
            'postgresql': PostgreSQLStore,
            's3': AmazonS3Store,
            'amazon_s3': AmazonS3Store,
            'gridfs': PostgreSQLStore,
            'tar': PostgreSQLStore
        }

        for path in path_lookup:
            store = _get_store_for_reading(
                download={'path': (path + ':')},
                amazon_s3_downloads_config=amazon_s3_downloads_config,
                download_storage_config=DoNotReadAllFromS3DownloadStorageConfig(),
            )
            expected_class = path_lookup[path]

            # isinstance() emits a warning in PyCharm
            assert type(store) == expected_class

        store = _get_store_for_reading(
            download={},
            amazon_s3_downloads_config=_default_amazon_s3_downloads_config(),
            download_storage_config=_default_download_storage_config(),
        )
        assert isinstance(store, AmazonS3Store)

        store = _get_store_for_reading(
            download={'path': 'nocolon'},
            amazon_s3_downloads_config=_default_amazon_s3_downloads_config(),
            download_storage_config=_default_download_storage_config(),
        )
        assert isinstance(store, AmazonS3Store)

        with self.assertRaises(McDBIDownloadsException):
            _get_store_for_reading(
                download={'path': 'invalidpath:'},
                amazon_s3_downloads_config=_default_amazon_s3_downloads_config(),
                download_storage_config=_default_download_storage_config(),
            )
