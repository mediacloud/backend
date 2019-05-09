from mediawords.dbi.downloads.store import store_content
# noinspection PyProtectedMember
from mediawords.tm.extract_story_links import _get_youtube_embed_links
from .setup_test_extract_story_links import TestExtractStoryLinksDB


class TestGetYouTubeEmbedLinks(TestExtractStoryLinksDB):

    def test_get_youtube_embed_links(self) -> None:

        youtube_html = """
        <iframe src="http://youtube.com/embed/1234" />
        <img src="http://foo.com/foo.png" />
        <iframe src="http://youtube-embed.com/embed/3456" />
        <iframe src="http://bar.com" />
        """

        store_content(self.db, self.test_download, youtube_html)

        links = _get_youtube_embed_links(self.db, self.test_story)

        assert links == ['http://youtube.com/embed/1234', 'http://youtube.com/embed/3456']
