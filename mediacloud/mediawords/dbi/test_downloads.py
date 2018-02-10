"""Test mediawords.dbi.downloads."""

import unittest

import mediawords.dbi.downloads
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.key_value_store.cached_amazon_s3 import CachedAmazonS3Store
from mediawords.key_value_store.database_inline import DatabaseInlineStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.key_value_store.multiple_stores import MultipleStoresStore

from mediawords.util.log import create_logger
log = create_logger(__name__)


class TestDownloads(unittest.TestCase):
    """Test case for downloads tests."""

    def setUp(self) -> None:
        """Set self.config and assign dummy values for amazon_s3."""
        self.config = mediawords.util.config.get_config()

        self._setup_amazon_s3_config()

    def tearDown(self) -> None:
        """Don't let global variables from one test to another."""
        mediawords.dbi.downloads.reset_store_singletons()

    def test_get_inline_store(self) -> None:
        """Test _get_inline_store."""
        store = mediawords.dbi.downloads._get_inline_store()

        assert isinstance(store, DatabaseInlineStore)

        # make sure the store is a singleton
        assert store is mediawords.dbi.downloads._get_inline_store()

    def _setup_amazon_s3_config(self) -> None:
        """Create amazon_s3 config with enough config values to test setting up the store."""
        if 'amazon_s3' not in self.config:
            self.config['amazon_s3'] = {'downloads': {}}

        for key in 'access_key_id secret_access_key bucket_name directory_name'.split():
            if key not in self.config['amazon_s3']['downloads']:
                self.config['amazon_s3']['downloads'][key] = 'foo'

    def test_get_amazon_s3_store(self) -> None:
        """Test _get_amazon_s3_store."""
        self.config['mediawords']['cache_s3_downloads'] = False
        store = mediawords.dbi.downloads._get_amazon_s3_store()

        assert isinstance(store, AmazonS3Store)

        assert store is mediawords.dbi.downloads._get_amazon_s3_store()

        mediawords.dbi.downloads._amazon_s3_store = None

        self.config['mediawords']['cache_s3_downloads'] = True
        store = mediawords.dbi.downloads._get_amazon_s3_store()

        assert isinstance(store, CachedAmazonS3Store)

        assert store is mediawords.dbi.downloads._get_amazon_s3_store()

    def test_get_postgresql_store(self) -> None:
        """Test _get_postgresql_store."""
        self.config['mediawords']['fallback_postgresql_downloads_to_s3'] = False
        store = mediawords.dbi.downloads._get_postgresql_store()

        assert isinstance(store, PostgreSQLStore)

        assert store is mediawords.dbi.downloads._get_postgresql_store()

        mediawords.dbi.downloads._postgresql_store = None

        self.config['mediawords']['fallback_postgresql_downloads_to_s3'] = True
        store = mediawords.dbi.downloads._get_postgresql_store()

        assert isinstance(store, MultipleStoresStore)

        assert store is mediawords.dbi.downloads._get_postgresql_store()

    def test_get_store_for_writing(self) -> None:
        """Test _get_store_for_writing."""
        self.config['mediawords']['download_storage_locations'] = []

        with self.assertRaises(mediawords.dbi.downloads.McDBIDownloadsException):
            mediawords.dbi.downloads._get_store_for_writing()

        self.config['mediawords']['download_storage_locations'] = ['s3', 'postgresql', 'databaseinline']

        with self.assertRaises(mediawords.dbi.downloads.McDBIDownloadsException):
            mediawords.dbi.downloads._get_store_for_writing()

        self.config['mediawords']['download_storage_locations'] = ['s3', 'postgresql']

        store = mediawords.dbi.downloads._get_store_for_writing()

        assert isinstance(store, MultipleStoresStore)

        stores = store.stores_for_writing()

        assert len(stores) == 2
        assert isinstance(stores[0], AmazonS3Store)
        assert isinstance(stores[1], PostgreSQLStore)

    def test_get_store_for_reading(self) -> None:
        """Test _get_store_for_reading."""
        self.config['mediawords']['read_all_downloads_from_s3'] = True

        store = mediawords.dbi.downloads._get_store_for_reading({'path': 'foo:'})
        assert isinstance(store, AmazonS3Store)

        store = mediawords.dbi.downloads._get_store_for_reading({'path': 'postgresql:'})
        assert isinstance(store, AmazonS3Store)

        self.config['mediawords']['read_all_downloads_from_s3'] = False
        self.config['mediawords']['fallback_postgresql_downloads_to_s3'] = False

        path_lookup = {
            'content': DatabaseInlineStore,
            'postgresql': PostgreSQLStore,
            's3': AmazonS3Store,
            'amazon_s3': AmazonS3Store,
            'gridfs': PostgreSQLStore,
            'tar': PostgreSQLStore
        }

        for path in path_lookup:
            store = mediawords.dbi.downloads._get_store_for_reading({'path': (path + ':')})
            assert isinstance(store, path_lookup[path])

        store = mediawords.dbi.downloads._get_store_for_reading({})
        assert isinstance(store, AmazonS3Store)

        store = mediawords.dbi.downloads._get_store_for_reading({'path': 'nocolon'})
        assert isinstance(store, AmazonS3Store)

        with self.assertRaises(mediawords.dbi.downloads.McDBIDownloadsException):
            mediawords.dbi.downloads._get_store_for_reading({'path': 'invalidpath:'})


class TestDBIDownloads(mediawords.test.test_database.TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.config = mediawords.util.config.get_config()

        self.test_medium = mediawords.test.db.create_test_medium(self.db(), 'downloads test')
        self.test_feed = mediawords.test.db.create_test_feed(self.db(), 'downlaods test', self.test_medium)
        self.test_download = mediawords.test.db.create_download_for_feed(self.db(), self.test_feed)

        self.test_download['path'] = 'postgresql:foo'
        self.test_download['state'] = 'success'
        self.db().update_by_id('downloads', self.test_download['downloads_id'], self.test_download)

    def tearDown(self) -> None:
        """Reset store singletons."""
        mediawords.dbi.downloads.reset_store_singletons()
        super().tearDown()

    def test_fetch_content(self) -> None:
        """Test fetch_content by manually storing using the postgrsql store and then trying to fetch it."""
        db = self.db()
        with self.assertRaises(mediawords.dbi.downloads.McDBIDownloadsException):
            mediawords.dbi.downloads.fetch_content(db, {})

        with self.assertRaises(mediawords.dbi.downloads.McDBIDownloadsException):
            mediawords.dbi.downloads.fetch_content(db, {'downloads_id': 1, 'state': 'error'})

        self.config['mediawords']['read_all_downloads_from_s3'] = False
        self.config['mediawords']['fallback_postgresql_downloads_to_s3'] = False

        content = 'foo bar'

        store = mediawords.dbi.downloads._get_store_for_reading(self.test_download)
        store.store_content(db, self.test_download['downloads_id'],  content)

        got_content = mediawords.dbi.downloads.fetch_content(db, self.test_download)

        assert got_content == content

        content = b'foo bar'

        store = mediawords.dbi.downloads._get_store_for_reading(self.test_download)
        store.store_content(db, self.test_download['downloads_id'],  content)

        got_content = mediawords.dbi.downloads.fetch_content(db, self.test_download)

        assert got_content == content.decode()
