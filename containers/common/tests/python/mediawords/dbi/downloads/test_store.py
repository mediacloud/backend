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
    store_content, fetch_content, get_media_id, get_medium, get_content_for_first_download)
from mediawords.test.db.create import (
    create_download_for_feed,
    create_test_feed,
    create_test_medium,
    create_test_story,
)
from mediawords.test.testing_database import TestDatabaseTestCase
from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.key_value_store.cached_amazon_s3 import CachedAmazonS3Store
from mediawords.key_value_store.database_inline import DatabaseInlineStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.key_value_store.multiple_stores import MultipleStoresStore
from mediawords.test.text import TestCaseTextUtilities
from mediawords.util.config.common import DownloadStorageConfig
from mediawords.util.log import create_logger

log = create_logger(__name__)


class TestDownloads(TestCase, TestCaseTextUtilities):
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


class TestDownloadsDB(TestDatabaseTestCase):
    """Run tests that require database access."""

    __TEST_CONTENT = '<script>ignore</script><p>foo</p>'

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.test_medium = create_test_medium(self.db(), 'downloads test')
        self.test_feed = create_test_feed(self.db(), 'downloads test', self.test_medium)
        self.test_download = create_download_for_feed(self.db(), self.test_feed)
        self.test_story = create_test_story(self.db(), label='downloads est', feed=self.test_feed)

        self.test_download['path'] = 'postgresql:foo'
        self.test_download['state'] = 'success'
        self.test_download['stories_id'] = self.test_story['stories_id']
        self.db().update_by_id('downloads', self.test_download['downloads_id'], self.test_download)

        store_content(db=self.db(), download=self.test_download, content=self.__TEST_CONTENT)

    def test_fetch_content(self) -> None:
        """Test fetch_content by manually storing using the PostgreSQL store and then trying to fetch it."""
        db = self.db()
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

    def test_store_content(self) -> None:
        """Test store_content by calling store_content and then calling fetch_content() on the postgresql store."""
        db = self.db()

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
        got_download = store_content(db=db, download=self.test_download, content=content)
        got_content = store.fetch_content(db=db, object_id=self.test_download['downloads_id']).decode()

        assert got_content == content
        assert got_download['state'] == 'success'
        assert got_download['path'] == 'postgresql:raw_downloads'
        assert got_download['error_message'] == ''

        content = 'bat baz bar'
        self.test_download['state'] = 'feed_error'
        got_download = store_content(db=db, download=self.test_download, content=content)
        got_content = store.fetch_content(db=db, object_id=self.test_download['downloads_id']).decode()

        assert got_content == content
        assert got_download['state'] == 'feed_error'
        assert got_download['path'] == 'postgresql:raw_downloads'
        assert not got_download['error_message']  # NULL or an empty string

    def test_get_media_id(self):
        media_id = get_media_id(db=self.db(), download=self.test_download)
        assert media_id == self.test_medium['media_id']

    def test_get_medium(self):
        medium = get_medium(db=self.db(), download=self.test_download)
        assert medium == self.test_medium

    def test_get_content_for_first_download(self):
        content = get_content_for_first_download(
            db=self.db(),
            story=self.test_story,
        )
        assert content == self.__TEST_CONTENT
