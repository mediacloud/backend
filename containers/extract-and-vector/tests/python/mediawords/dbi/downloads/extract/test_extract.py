from mediawords.dbi.downloads.extract import extract
from mediawords.dbi.downloads.extract.setup_test_extract import TestExtractDB
from mediawords.dbi.downloads.store import store_content
from mediawords.dbi.stories.extractor_arguments import PyExtractorArguments


class TestExtract(TestExtractDB):
    """Run tests that require database access."""

    def test_extract(self) -> None:
        """Test extract()."""

        html = '<script>ignore</script><p>foo</p>'
        store_content(self.db, self.test_download, html)
        result = extract(db=self.db, download=self.test_download)

        assert result['extracted_html'].strip() == '<body id="readabilityBody"><p>foo</p></body>'
        assert result['extracted_text'].strip() == 'foo.'

        store_content(self.db, self.test_download, html)
        extract(
            db=self.db,
            download=self.test_download,
            extractor_args=PyExtractorArguments(use_cache=True),
        )
        store_content(self.db, self.test_download, 'bar')
        result = extract(
            db=self.db,
            download=self.test_download,
            extractor_args=PyExtractorArguments(use_cache=True),
        )
        assert result['extracted_html'].strip() == '<body id="readabilityBody"><p>foo</p></body>'
        assert result['extracted_text'].strip() == 'foo.'
