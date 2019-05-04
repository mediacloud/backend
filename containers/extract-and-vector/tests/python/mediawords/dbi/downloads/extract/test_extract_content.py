import os
from unittest import TestCase

from mediawords.test.data import fetch_test_data_from_individual_files

from mediawords.dbi.downloads.extract import extract_content
from mediawords.test.text import TestCaseTextUtilities


class TestExtractContent(TestCase, TestCaseTextUtilities):

    def test_extract_content_basic(self) -> None:
        """Test extract_content()."""
        results = extract_content("<script>foo<</script><p>bar</p>")
        assert results['extracted_html'].strip() == '<body id="readabilityBody"><p>bar</p></body>'
        assert results['extracted_text'].strip() == 'bar.'

        results = extract_content('foo')
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

        path = os.path.join('/opt/mediacloud/tests/data/crawler/', test_dataset, test_file)

        with open(path, mode='r', encoding='utf-8') as f:
            content = f.read()
            results = extract_content(content=content)
            extracted_text = results['extracted_text']

            # FIXME make the crawler and extractor come up with an identical extracted text object and compare those
            assert len(extracted_text) > 7000, "Extracted text length looks reasonable."
            assert '<' not in extracted_text, "No HTML tags left in extracted text."
