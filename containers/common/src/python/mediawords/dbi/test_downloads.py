"""Test mediawords.dbi.downloads."""

import copy
import os
import unittest

import mediawords.dbi.downloads
from mediawords.dbi.stories.extract import combine_story_title_description_text
from mediawords.dbi.stories.extractor_arguments import PyExtractorArguments
from mediawords.test.data import fetch_test_data_from_individual_files, get_path_to_data_files
from mediawords.test.db.create import create_download_for_feed, create_test_feed, create_test_medium, create_test_story
from mediawords.test.test_database import TestDatabaseWithSchemaTestCase
from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.key_value_store.cached_amazon_s3 import CachedAmazonS3Store
from mediawords.key_value_store.database_inline import DatabaseInlineStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.key_value_store.multiple_stores import MultipleStoresStore
from mediawords.test.text import TestCaseTextUtilities
from mediawords.util.config import get_config
from mediawords.util.log import create_logger

log = create_logger(__name__)


class TestDownloads(unittest.TestCase, TestCaseTextUtilities):
    """Test case for downloads tests."""

    def setUp(self) -> None:
        """Set self.config and assign dummy values for amazon_s3."""
        self.config = get_config()
        self.save_config = copy.deepcopy(self.config)

        self._setup_amazon_s3_config()

    def tearDown(self) -> None:
        """Don't let global variables from one test to another."""
        mediawords.dbi.downloads.reset_store_singletons()
        mediawords.util.config.set_config(self.save_config)

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
            expected_class = path_lookup[path]

            # isinstance() emits a warning in PyCharm
            assert type(store) == expected_class

        store = mediawords.dbi.downloads._get_store_for_reading({})
        assert isinstance(store, AmazonS3Store)

        store = mediawords.dbi.downloads._get_store_for_reading({'path': 'nocolon'})
        assert isinstance(store, AmazonS3Store)

        with self.assertRaises(mediawords.dbi.downloads.McDBIDownloadsException):
            mediawords.dbi.downloads._get_store_for_reading({'path': 'invalidpath:'})

    def test_extract_content_basic(self) -> None:
        """Test extract_content()."""
        results = mediawords.dbi.downloads.extract_content("<script>foo<</script><p>bar</p>")
        assert results['extracted_html'].strip() == '<body id="readabilityBody"><p>bar</p></body>'
        assert results['extracted_text'].strip() == 'bar.'

        results = mediawords.dbi.downloads.extract_content('foo')
        assert results['extracted_html'].strip() == 'foo'
        assert results['extracted_text'].strip() == 'foo'

    def test_extract_content_extended(self):

        test_dataset = 'gv'
        test_file = 'index_1.html'
        test_title = 'Brazil: Amplified conversations to fight the Digital Crimes Bill'

        test_stories = fetch_test_data_from_individual_files(basename="crawler_stories/{}".format(test_dataset))

        test_story_hash = {}
        for story in test_stories:
            test_story_hash[story['title']] = story

        story = test_story_hash.get(test_title, None)
        assert story, "Story with title '{}' was not found.".format(test_title)

        data_files_path = get_path_to_data_files(subdirectory='crawler/{}'.format(test_dataset))
        path = os.path.join(data_files_path, test_file)

        with open(path, mode='r', encoding='utf-8') as f:
            content = f.read()
            results = mediawords.dbi.downloads.extract_content(content=content)

            # Crawler test squeezes in story title and description into the expected output
            combined_text = combine_story_title_description_text(
                story_title=story['title'],
                story_description=story['description'],
                download_texts=[
                    results['extracted_text'],
                ],
            )

            expected_text = story['extracted_text']
            actual_text = combined_text

            self.assertTextEqual(got_text=actual_text, expected_text=expected_text)


class TestDownloadsDB(TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    __TEST_CONTENT = '<script>ignore</script><p>foo</p>'

    def setUp(self) -> None:
        """Set config for tests."""
        super().setUp()

        self.config = mediawords.util.config.get_config()

        self.test_medium = create_test_medium(self.db(), 'downloads test')
        self.test_feed = create_test_feed(self.db(), 'downloads test', self.test_medium)
        self.test_download = create_download_for_feed(self.db(), self.test_feed)
        self.test_story = create_test_story(self.db(), label='downloads est', feed=self.test_feed)

        self.test_download['path'] = 'postgresql:foo'
        self.test_download['state'] = 'success'
        self.test_download['stories_id'] = self.test_story['stories_id']
        self.db().update_by_id('downloads', self.test_download['downloads_id'], self.test_download)

        mediawords.dbi.downloads.store_content(self.db(), self.test_download, self.__TEST_CONTENT)

        self.save_config = copy.deepcopy(self.config)

    def tearDown(self) -> None:
        """Reset store singletons."""
        mediawords.dbi.downloads.reset_store_singletons()
        mediawords.util.config.set_config(self.save_config)
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

        store = mediawords.dbi.downloads._get_store_for_reading(self.test_download)

        content = 'foo bar'
        store.store_content(db, self.test_download['downloads_id'], content)
        got_content = mediawords.dbi.downloads.fetch_content(db, self.test_download)
        assert got_content == content

        content = b'foo bar'
        store.store_content(db, self.test_download['downloads_id'], content)
        got_content = mediawords.dbi.downloads.fetch_content(db, self.test_download)
        assert got_content == content.decode()

        self.config['mediawords']['ascii_hack_downloads_id'] = 100
        content = 'foo \xAD bar'
        store.store_content(db, self.test_download['downloads_id'], content)
        got_content = mediawords.dbi.downloads.fetch_content(db, self.test_download)
        assert got_content == 'foo   bar'

    def test_store_content(self) -> None:
        """Test store_content by calling store_content and then calling fetch_content() on the postgresql store."""
        db = self.db()

        self.config['mediawords']['read_all_downloads_from_s3'] = False
        self.config['mediawords']['fallback_postgresql_downloads_to_s3'] = False
        self.config['mediawords']['storage_locations'] = 'postgresql'

        store = mediawords.dbi.downloads._get_store_for_reading(self.test_download)

        content = 'bat baz bar foo'
        got_download = mediawords.dbi.downloads.store_content(db, self.test_download, content)
        got_content = store.fetch_content(db, self.test_download['downloads_id']).decode()

        assert got_content == content
        assert got_download['state'] == 'success'
        assert got_download['path'] == 'postgresql:raw_downloads'
        assert got_download['error_message'] == ''

        content = 'bat baz bar'
        self.test_download['state'] = 'feed_error'
        got_download = mediawords.dbi.downloads.store_content(db, self.test_download, content)
        got_content = store.fetch_content(db, self.test_download['downloads_id']).decode()

        assert got_content == content
        assert got_download['state'] == 'feed_error'
        assert got_download['path'] == 'postgresql:raw_downloads'
        assert not got_download['error_message']  # NULL or an empty string

    def test_extractor_cache(self) -> None:
        """Test set and get for extract cache."""
        extractor_results = {'extracted_html': 'extracted html', 'extracted_text': 'extracted text'}
        mediawords.dbi.downloads._set_cached_extractor_results(self.db(), self.test_download, extractor_results)
        got_results = mediawords.dbi.downloads._get_cached_extractor_results(self.db(), self.test_download)
        assert got_results == extractor_results

    def test_extract(self) -> None:
        """Test extract()."""
        db = self.db()

        html = '<script>ignore</script><p>foo</p>'
        mediawords.dbi.downloads.store_content(db, self.test_download, html)
        result = mediawords.dbi.downloads.extract(db=db, download=self.test_download)

        assert result['extracted_html'].strip() == '<body id="readabilityBody"><p>foo</p></body>'
        assert result['extracted_text'].strip() == 'foo.'

        mediawords.dbi.downloads.store_content(db, self.test_download, html)
        mediawords.dbi.downloads.extract(
            db=db,
            download=self.test_download,
            extractor_args=PyExtractorArguments(use_cache=True),
        )
        mediawords.dbi.downloads.store_content(db, self.test_download, 'bar')
        result = mediawords.dbi.downloads.extract(
            db=db,
            download=self.test_download,
            extractor_args=PyExtractorArguments(use_cache=True),
        )
        assert result['extracted_html'].strip() == '<body id="readabilityBody"><p>foo</p></body>'
        assert result['extracted_text'].strip() == 'foo.'

    def test_get_media_id(self):
        media_id = mediawords.dbi.downloads.get_media_id(db=self.db(), download=self.test_download)
        assert media_id == self.test_medium['media_id']

    def test_get_medium(self):
        medium = mediawords.dbi.downloads.get_medium(db=self.db(), download=self.test_download)
        assert medium == self.test_medium

    def test_extract_and_create_download_text(self):
        download_text = mediawords.dbi.downloads.extract_and_create_download_text(
            db=self.db(),
            download=self.test_download,
            extractor_args=PyExtractorArguments(),
        )

        assert download_text
        assert download_text['download_text'] == 'foo.'
        assert download_text['downloads_id'] == self.test_download['downloads_id']

    def test_process_download_for_extractor(self):
        # Make sure nothing's extracted yet and download text is not to be found
        assert len(self.db().select(
            table='story_sentences',
            what_to_select='*',
            condition_hash={'stories_id': self.test_download['stories_id']},
        ).hashes()) == 0
        assert len(self.db().select(
            table='download_texts',
            what_to_select='*',
            condition_hash={'downloads_id': self.test_download['downloads_id']},
        ).hashes()) == 0

        mediawords.dbi.downloads.process_download_for_extractor(db=self.db(), download=self.test_download)

        # We expect the download to be extracted and the story to be processed
        assert len(self.db().select(
            table='story_sentences',
            what_to_select='*',
            condition_hash={'stories_id': self.test_download['stories_id']},
        ).hashes()) > 0
        assert len(self.db().select(
            table='download_texts',
            what_to_select='*',
            condition_hash={'downloads_id': self.test_download['downloads_id']},
        ).hashes()) > 0

    def test_get_content_for_first_download(self):
        content = mediawords.dbi.downloads.get_content_for_first_download(
            db=self.db(),
            story=self.test_story,
        )
        assert content == self.__TEST_CONTENT
