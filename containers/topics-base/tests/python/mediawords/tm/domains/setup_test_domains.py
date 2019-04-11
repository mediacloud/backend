from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.tm.domains import increment_domain_links
from mediawords.test.db.create import create_test_topic, create_test_medium, create_test_feed, create_test_story


class TestTMDomainsDB(TestCase):
    """Run tests that require database access."""

    def setUp(self):
        super().setUp()

        self.db = connect_to_db()

        self.topic = create_test_topic(self.db, 'foo')
        self.medium = create_test_medium(self.db, 'bar')
        self.feed = create_test_feed(self.db, 'baz', self.medium)
        self.story = create_test_story(self.db, 'bat', self.feed)

        self.db.create('topic_stories', {'topics_id': self.topic['topics_id'], 'stories_id': self.story['stories_id']})

    def create_topic_link(self, topic: dict, story: dict, url: str, redirect_url: str) -> dict:
        """Create a topic_link db row."""
        topic_link = {
            'topics_id': topic['topics_id'],
            'stories_id': story['stories_id'],
            'url': url,
            'redirect_url': redirect_url
        }

        topic_link = self.db.create('topic_links', topic_link)

        increment_domain_links(self.db, topic_link)

        return topic_link

    def get_topic_domain(self, topic: dict, domain: str) -> dict:
        """Get a topic_domain."""
        return self.db.query(
            'select * from topic_domains where topics_id = %(a)s and domain = %(b)s',
            {'a': topic['topics_id'], 'b': domain}).hash()
