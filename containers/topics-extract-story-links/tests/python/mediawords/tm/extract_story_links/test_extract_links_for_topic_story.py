#!/usr/bin/env py.test

from mediawords.test.db.create import create_test_topic
from mediawords.tm.extract_story_links.setup_test_extract_story_links import TestExtractStoryLinksDB
from mediawords.tm.extract_story_links import extract_links_for_topic_story


class TestExtractLinksForTopicStory(TestExtractStoryLinksDB):

    def test_extract_links_for_topic_story(self) -> None:
        """Test extract_links_for_topic_story()."""

        self.test_story['description'] = 'http://foo.com http://bar.com'
        self.db.update_by_id('stories', self.test_story['stories_id'], self.test_story)

        topic = create_test_topic(self.db, 'links')
        self.db.create('topic_stories', {'topics_id': topic['topics_id'], 'stories_id': self.test_story['stories_id']})

        extract_links_for_topic_story(
            db=self.db,
            stories_id=self.test_story['stories_id'],
            topics_id=topic['topics_id'],
        )

        got_topic_links = self.db.query(
            "select topics_id, stories_id, url from topic_links where topics_id = %(a)s order by url",
            {'a': topic['topics_id']}).hashes()

        expected_topic_links = [
            {'topics_id': topic['topics_id'], 'stories_id': self.test_story['stories_id'], 'url': 'http://bar.com'},
            {'topics_id': topic['topics_id'], 'stories_id': self.test_story['stories_id'], 'url': 'http://foo.com'}]

        assert got_topic_links == expected_topic_links

        got_topic_story = self.db.query(
            "select topics_id, stories_id, link_mined from topic_stories where topics_id =%(a)s and stories_id = %(b)s",
            {'a': topic['topics_id'], 'b': self.test_story['stories_id']}).hash()

        expected_topic_story = {
            'topics_id': topic['topics_id'],
            'stories_id': self.test_story['stories_id'],
            'link_mined': True,
        }

        assert got_topic_story == expected_topic_story

        # generate an error and make sure that it gets saved to topic_stories
        del self.test_story['url']
        extract_links_for_topic_story(db=self.db, stories_id=self.test_story['stories_id'],
                                      topics_id=topic['topics_id'])

        got_topic_story = self.db.query(
            """
            select topics_id, stories_id, link_mined, link_mine_error
                from topic_stories
                where topics_id =%(a)s and stories_id = %(b)s
            """,
            {'a': topic['topics_id'], 'b': self.test_story['stories_id']}).hash()

        assert "KeyError: 'url'" in got_topic_story['link_mine_error']
        assert got_topic_story['link_mined']
