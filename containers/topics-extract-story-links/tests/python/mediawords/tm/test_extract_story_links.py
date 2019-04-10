#!/usr/bin/env py.test

"""Test mediawords.tm.extract_story_links."""
from mediawords.dbi.downloads.store import store_content
from mediawords.test.db.create import create_test_story_stack, create_download_for_story, create_test_topic
from mediawords.test.testing_database import TestDatabaseTestCase
from mediawords.tm.domains import MAX_SELF_LINKS
# noinspection PyProtectedMember
from mediawords.tm.extract_story_links import (
    _get_links_from_html,
    _get_youtube_embed_links,
    _get_extracted_html,
    _get_links_from_story_text,
    _get_links_from_story,
    extract_links_for_topic_story,
)
from mediawords.util.url import is_http_url, get_url_distinctive_domain


def test_get_links_from_html() -> None:
    """Test get_links_from_html()."""

    def test_links(html_: str, links_: list) -> None:
        assert _get_links_from_html(html_) == links_

    test_links('<a href="http://foo.com">', ['http://foo.com'])
    test_links('<link href="http://bar.com">', ['http://bar.com'])
    test_links('<img src="http://img.tag">', [])

    test_links('<a href="http://foo.com"/> <a href="http://bar.com"/>', ['http://foo.com', 'http://bar.com'])

    # transform nyt urls
    test_links('<a href="http://www3.nytimes.com/foo/bar">', ['http://www.nytimes.com/foo/bar'])

    # ignore relative urls
    test_links('<a href="/foo/bar">', [])

    # ignore invalid urls
    test_links(r'<a href="http:\\foo.bar">', [])

    # ignore urls from ignore pattern
    test_links('<a href="http://www.addtoany.com/http://foo.bar">', [])
    test_links('<a href="https://en.unionpedia.org/c/SOE_F_Section_timeline/vs/Special_Operations_Executive">', [])
    test_links('<a href="http://digg.com/submit/this">', [])
    test_links('<a href="http://politicalgraveyard.com/>', [])
    test_links('<a href="http://api.bleacherreport.com/api/v1/tags/cm-punk.json">', [])
    test_links('<a href="http://apidomain.com">', ['http://apidomain.com'])
    test_links('<a href="http://www.rumormillnews.com/cgi-bin/forum.cgi?noframes;read=54990">', [])
    test_links('<a href="http://tvtropes.org/pmwiki/pmwiki.php/Main/ClockTower">', [])
    test_links('<a href=https://twitter.com/account/suspended">', [])

    # sanity test to make sure that we are able to get all of the links from a real html page
    filename = '/mediacloud/test-data/html-strip/strip.html'
    with open(filename, 'r', encoding='utf8') as fh:
        html = fh.read()

    links = _get_links_from_html(html)
    assert len(links) == 300
    for link in links:
        assert is_http_url(link)


class TestExtractStoryLinksDB(TestDatabaseTestCase):
    """Run tests that require database access."""

    def setUp(self) -> None:
        """Create test_story and test_download."""
        super().setUp()
        db = self.db()

        media = create_test_story_stack(db, {'A': {'B': [1]}})

        story = media['A']['feeds']['B']['stories']['1']

        download = create_download_for_story(
            db=db,
            feed=media['A']['feeds']['B'],
            story=story,
        )

        store_content(db, download, '<p>foo</p>')

        self.test_story = story
        self.test_download = download

    def test_get_youtube_embed_links(self) -> None:
        """Test get_youtube_embed_links()."""
        db = self.db()

        story = self.test_story
        download = self.test_download

        youtube_html = """
        <iframe src="http://youtube.com/embed/1234" />
        <img src="http://foo.com/foo.png" />
        <iframe src="http://youtube-embed.com/embed/3456" />
        <iframe src="http://bar.com" />
        """

        store_content(db, download, youtube_html)

        links = _get_youtube_embed_links(db, story)

        assert links == ['http://youtube.com/embed/1234', 'http://youtube.com/embed/3456']

    def test_get_extracted_html(self) -> None:
        """Test _get_extracted_html()."""
        db = self.db()

        story = self.test_story
        download = self.test_download

        content = '<html><head><meta foo="bar" /></head><body>foo</body></html>'

        store_content(db, download, content)

        extracted_html = _get_extracted_html(db, story)

        assert extracted_html.strip() == '<body id="readabilityBody">foo</body>'

    def test_get_links_from_story_text(self) -> None:
        """Test get_links_from_story_text()."""
        db = self.db()

        story = self.test_story
        download = self.test_download

        story['title'] = 'http://title.com/'
        story['description'] = 'http://description.com'
        db.update_by_id('stories', story['stories_id'], story)

        db.create('download_texts', {
            'downloads_id': download['downloads_id'],
            'download_text': 'http://download.text',
            'download_text_length': 20})

        links = _get_links_from_story_text(db, story)

        assert sorted(links) == sorted('http://title.com http://description.com http://download.text'.split())

    def test_get_links_from_story(self) -> None:
        """Test get_links_from_story()."""
        db = self.db()

        story = self.test_story
        download = self.test_download

        story['title'] = 'http://title.text'
        story['description'] = '<a href="http://description.link" />http://description.text'
        db.update_by_id('stories', story['stories_id'], story)

        html_content = """
        <p>Here is a content <a href="http://content.1.link">link</a>.</p>
        <p>Here is another content <a href="http://content.2.link" />link</a>.</p>
        <p>Here is a duplicate content <a href="http://content.2.link" />link</a>.</p>
        <p>Here is a duplicate text <a href="http://link-text.dup" />link</a>.</p>
        <p>Here is a youtube embed:</p>
        <iframe src="http://youtube-embed.com/embed/123456" />
        """

        download_text = dict()
        download_text['downloads_id'] = download['downloads_id']
        download_text['download_text'] = "http://text.1.link http://text.2.link http://text.2.link http://link-text.dup"
        download_text['download_text_length'] = len(download_text['download_text'])
        db.create('download_texts', download_text)

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

        store_content(db, download, html_content)

        links = _get_links_from_story(db, story)

        assert sorted(links) == sorted(expected_links)

    def test_extract_links_for_topic_story(self) -> None:
        """Test extract_links_for_topic_story()."""
        db = self.db()

        story = self.test_story

        story['description'] = 'http://foo.com http://bar.com'
        db.update_by_id('stories', story['stories_id'], story)

        topic = create_test_topic(db, 'links')
        db.create('topic_stories', {'topics_id': topic['topics_id'], 'stories_id': story['stories_id']})

        extract_links_for_topic_story(db=db, stories_id=story['stories_id'], topics_id=topic['topics_id'])

        got_topic_links = db.query(
            "select topics_id, stories_id, url from topic_links where topics_id = %(a)s order by url",
            {'a': topic['topics_id']}).hashes()

        expected_topic_links = [
            {'topics_id': topic['topics_id'], 'stories_id': story['stories_id'], 'url': 'http://bar.com'},
            {'topics_id': topic['topics_id'], 'stories_id': story['stories_id'], 'url': 'http://foo.com'}]

        assert got_topic_links == expected_topic_links

        got_topic_story = db.query(
            "select topics_id, stories_id, link_mined from topic_stories where topics_id =%(a)s and stories_id = %(b)s",
            {'a': topic['topics_id'], 'b': story['stories_id']}).hash()

        expected_topic_story = {'topics_id': topic['topics_id'], 'stories_id': story['stories_id'], 'link_mined': True}

        assert got_topic_story == expected_topic_story

        # generate an error and make sure that it gets saved to topic_stories
        del story['url']
        extract_links_for_topic_story(db=db, stories_id=story['stories_id'], topics_id=topic['topics_id'])

        got_topic_story = db.query(
            """
            select topics_id, stories_id, link_mined, link_mine_error
                from topic_stories
                where topics_id =%(a)s and stories_id = %(b)s
            """,
            {'a': topic['topics_id'], 'b': story['stories_id']}).hash()

        assert "KeyError: 'url'" in got_topic_story['link_mine_error']
        assert got_topic_story['link_mined']

    def test_skip_self_links(self) -> None:
        """Test that self links are skipped within extract_links_for_topic_story"""
        db = self.db()

        story = self.test_story

        story_domain = get_url_distinctive_domain(story['url'])

        topic = create_test_topic(db, 'links')
        db.create('topic_stories', {'topics_id': topic['topics_id'], 'stories_id': story['stories_id']})

        num_links = MAX_SELF_LINKS * 2
        content = ''
        for i in range(num_links):
            plain_text = "Sample sentence to make sure the links get extracted" * 10
            url = "http://%s/%d" % (story_domain, i)
            paragraph = "<p>%s <a href='%s'>link</a></p>\n\n" % (plain_text, url)
            content = content + paragraph

        store_content(db, self.test_download, content)

        extract_links_for_topic_story(db=db, stories_id=story['stories_id'], topics_id=topic['topics_id'])

        topic_links = db.query("select * from topic_links where topics_id = %(a)s", {'a': topic['topics_id']}).hashes()

        assert (len(topic_links) == MAX_SELF_LINKS)
