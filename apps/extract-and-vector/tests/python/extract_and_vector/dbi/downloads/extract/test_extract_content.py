from unittest import TestCase

from mediawords.test.text import TestCaseTextUtilities
from extract_and_vector.dbi.downloads.extract import extract_content


class TestExtractContent(TestCase, TestCaseTextUtilities):

    def test_extract_content(self) -> None:
        """Basic test for extract_content()."""
        results = extract_content("<script>foo<</script><p>bar</p>")
        assert results['extracted_html'].strip() == '<body id="readabilityBody"><p>bar</p></body>'
        assert results['extracted_text'].strip() == 'bar.'

        results = extract_content('foo')
        assert results['extracted_html'].strip() == 'foo'
        assert results['extracted_text'].strip() == 'foo'
