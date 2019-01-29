import os

from mediawords.test.data import fetch_test_data_from_individual_files, get_path_to_data_files



class TestExtract(TestCase, TestCaseTextUtilities):

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
            extracted_text = results['extracted_text']

            # FIXME make the crawler and extractor come up with an identical extracted text object and compare those
            assert len(extracted_text) > 7000, "Extracted text length looks reasonable."
            assert '<' not in extracted_text, "No HTML tags left in extracted text."



class TestExtractDB(TestDatabaseWithSchemaTestCase):
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
