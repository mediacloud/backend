# noinspection PyProtectedMember
from mediawords.tm.extract_story_links import _get_links_from_story_text
from .setup_test_extract_story_links import TestExtractStoryLinksDB


class TestGetLinksFromStoryText(TestExtractStoryLinksDB):

    def test_get_links_from_story_text(self) -> None:
        self.test_story['title'] = 'http://title.com/'
        self.test_story['description'] = 'http://description.com'
        self.db.update_by_id('stories', self.test_story['stories_id'], self.test_story)

        self.db.create('download_texts', {
            'downloads_id': self.test_download['downloads_id'],
            'download_text': 'http://download.text',
            'download_text_length': 20})

        links = _get_links_from_story_text(self.db, self.test_story)

        assert sorted(links) == sorted('http://title.com http://description.com http://download.text'.split())
