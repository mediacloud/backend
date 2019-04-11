#!/usr/bin/env py.test

from mediawords.dbi.downloads.store import store_content
# noinspection PyProtectedMember
from mediawords.tm.extract_story_links import _get_links_from_story
from mediawords.tm.extract_story_links.setup_test_extract_story_links import TestExtractStoryLinksDB


class TestGetLinksFromStory(TestExtractStoryLinksDB):

    def test_get_links_from_story(self):
        """Test get_links_from_story()."""

        self.test_story['title'] = 'http://title.text'
        self.test_story['description'] = '<a href="http://description.link" />http://description.text'
        self.db.update_by_id('stories', self.test_story['stories_id'], self.test_story)

        html_content = """
        <p>Here is a content <a href="http://content.1.link">link</a>.</p>
        <p>Here is another content <a href="http://content.2.link" />link</a>.</p>
        <p>Here is a duplicate content <a href="http://content.2.link" />link</a>.</p>
        <p>Here is a duplicate text <a href="http://link-text.dup" />link</a>.</p>
        <p>Here is a youtube embed:</p>
        <iframe src="http://youtube-embed.com/embed/123456" />
        """

        download_text = dict()
        download_text['downloads_id'] = self.test_download['downloads_id']
        download_text['download_text'] = "http://text.1.link http://text.2.link http://text.2.link http://link-text.dup"
        download_text['download_text_length'] = len(download_text['download_text'])
        self.db.create('download_texts', download_text)

        expected_links = """
        http://content.1.link
        http://content.2.link
        http://youtube.com/embed/123456
        http://title.text
        http://description.link
        http://description.text
        http://text.1.link
        http://text.2.link
        http://link-text.dup
        """.split()

        store_content(self.db, self.test_download, html_content)

        links = _get_links_from_story(self.db, self.test_story)

        assert sorted(links) == sorted(expected_links)
