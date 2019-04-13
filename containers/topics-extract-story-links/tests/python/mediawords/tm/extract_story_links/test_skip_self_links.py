from mediawords.dbi.downloads.store import store_content
from mediawords.test.db.create import create_test_topic
from mediawords.tm.domains import MAX_SELF_LINKS
from mediawords.tm.extract_story_links import extract_links_for_topic_story
from mediawords.tm.extract_story_links.setup_test_extract_story_links import TestExtractStoryLinksDB
from mediawords.util.url import get_url_distinctive_domain


class TestSkipSelfLinks(TestExtractStoryLinksDB):

    def test_skip_self_links(self):
        """Test that self links are skipped within extract_links_for_topic_story"""

        story_domain = get_url_distinctive_domain(self.test_story['url'])

        topic = create_test_topic(self.db, 'links')
        self.db.create('topic_stories', {'topics_id': topic['topics_id'], 'stories_id': self.test_story['stories_id']})

        num_links = MAX_SELF_LINKS * 2
        content = ''
        for i in range(num_links):
            plain_text = "Sample sentence to make sure the links get extracted" * 10
            url = "http://%s/%d" % (story_domain, i)
            paragraph = "<p>%s <a href='%s'>link</a></p>\n\n" % (plain_text, url)
            content = content + paragraph

        store_content(self.db, self.test_download, content)

        extract_links_for_topic_story(db=self.db,
                                      stories_id=self.test_story['stories_id'],
                                      topics_id=topic['topics_id'])

        topic_links = self.db.query("select * from topic_links where topics_id = %(a)s",
                                    {'a': topic['topics_id']}).hashes()

        assert (len(topic_links) == MAX_SELF_LINKS)
