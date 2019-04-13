from mediawords.dbi.downloads.extract.setup_test_extract import TestExtractDB
from mediawords.dbi.downloads.extract import process_download_for_extractor


class TestProcessDownloadForExtractor(TestExtractDB):
    """Run tests that require database access."""

    def test_process_download_for_extractor(self):
        # Make sure nothing's extracted yet and download text is not to be found
        assert len(self.db.select(
            table='story_sentences',
            what_to_select='*',
            condition_hash={'stories_id': self.test_download['stories_id']},
        ).hashes()) == 0
        assert len(self.db.select(
            table='download_texts',
            what_to_select='*',
            condition_hash={'downloads_id': self.test_download['downloads_id']},
        ).hashes()) == 0

        process_download_for_extractor(db=self.db, download=self.test_download)

        # We expect the download to be extracted and the story to be processed
        assert len(self.db.select(
            table='story_sentences',
            what_to_select='*',
            condition_hash={'stories_id': self.test_download['stories_id']},
        ).hashes()) > 0
        assert len(self.db.select(
            table='download_texts',
            what_to_select='*',
            condition_hash={'downloads_id': self.test_download['downloads_id']},
        ).hashes()) > 0
