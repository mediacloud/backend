#!/usr/bin/env py.test

from mediawords.dbi.downloads.store import store_content
# noinspection PyProtectedMember
from mediawords.tm.extract_story_links import _get_extracted_html
from mediawords.tm.extract_story_links.setup_test_extract_story_links import TestExtractStoryLinksDB


class TestGetExtractedHTML(TestExtractStoryLinksDB):

    def test_get_extracted_html(self) -> None:
        content = '<html><head><meta foo="bar" /></head><body>foo</body></html>'

        store_content(self.db, self.test_download, content)

        extracted_html = _get_extracted_html(self.db, self.test_story)

        assert extracted_html.strip() == '<body id="readabilityBody">foo</body>'
