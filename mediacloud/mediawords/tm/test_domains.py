""" Test mediawords.tm.domains. """

import mediawords.db
from mediawords.db import DatabaseHandler
import mediawords.test.db.create
import mediawords.test.test_database
import mediawords.tm.domains
import mediawords.util.url


def _create_topic_link(db: DatabaseHandler, topic: dict, story: dict, url: str, redirect_url: str) -> dict:
    """Create a topic_link db row."""
    topic_link = {
        'topics_id': topic['topics_id'],
        'stories_id': story['stories_id'],
        'url': url,
        'redirect_url': redirect_url
    }

    topic_link = db.create('topic_links', topic_link)

    mediawords.tm.domains.increment_domain_links(db, topic_link)

    return topic_link


def _get_topic_domain(db: DatabaseHandler, topic: dict, domain: str) -> dict:
    """Get a topic_domain."""
    return db.query(
        'select * from topic_domains where topics_id = %(a)s and domain = %(b)s',
        {'a': topic['topics_id'], 'b': domain}).hash()


class TestTMDomainsDB(mediawords.test.test_database.TestDatabaseWithSchemaTestCase):
    """Run tests that require database access."""

    def test_increment_domain_links(self) -> None:
        """Test incremeber_domain_links9()."""
        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'foo')
        medium = mediawords.test.db.create.create_test_medium(db, 'bar')
        feed = mediawords.test.db.create.create_test_feed(db, 'baz', medium)
        story = mediawords.test.db.create.create_test_story(db, 'bat', feed)

        db.create('topic_stories', {'topics_id': topic['topics_id'], 'stories_id': story['stories_id']})

        nomatch_domain = 'no.match'
        story_domain = mediawords.util.url.get_url_distinctive_domain(story['url'])

        num_url_matches = 3
        for i in range(num_url_matches):
            _create_topic_link(db, topic, story, story_domain, nomatch_domain)
            td = _get_topic_domain(db, topic, nomatch_domain)

            assert(td is not None)
            assert(td['self_links'] == i + 1)

        num_redirect_matches = 3
        for i in range(num_redirect_matches):
            _create_topic_link(db, topic, story, nomatch_domain, story_domain)
            td = _get_topic_domain(db, topic, story_domain)

            assert(td is not None)
            assert(td['self_links'] == i + 1)

    def test_skip_self_linked_domain(self) -> None:
        """Test skip_self_linked_domain."""

        db = self.db()

        topic = mediawords.test.db.create.create_test_topic(db, 'foo')
        medium = mediawords.test.db.create.create_test_medium(db, 'bar')
        feed = mediawords.test.db.create.create_test_feed(db, 'baz', medium)
        story = mediawords.test.db.create.create_test_story(db, 'bat', feed)

        db.create('topic_stories', {'topics_id': topic['topics_id'], 'stories_id': story['stories_id']})

        # no topic_links_id should always return False
        assert(mediawords.tm.domains.skip_self_linked_domain(db, {}) is False)

        # always skip search type pages
        story_domain = mediawords.util.url.get_url_distinctive_domain(story['url'])
        regex_skipped_urls = ['http://%s/%s' % (story_domain, suffix) for suffix in ['search', 'author', 'tag']]
        for url in regex_skipped_urls:
            tl = _create_topic_link(db, topic, story, url, url)
            assert(mediawords.tm.domains.skip_self_linked_domain(db, tl) is True)

        self_domain_url = 'http://%s/foo/bar' % story_domain
        for i in range(mediawords.tm.domains.MAX_SELF_LINKS - len(regex_skipped_urls) - 1):
            url = self_domain_url + str(i)
            tl = _create_topic_link(db, topic, story, url, url)
            assert(mediawords.tm.domains.skip_self_linked_domain(db, tl) is False)

        num_tested_skipped_urls = 10
        for i in range(num_tested_skipped_urls):
            tl = _create_topic_link(db, topic, story, self_domain_url, self_domain_url)
            assert(mediawords.tm.domains.skip_self_linked_domain(db, tl) is True)

        other_domain_url = 'http://other.domain/foo/bar'
        num_tested_other_urls = 10
        for i in range(num_tested_other_urls):
            tl = _create_topic_link(db, topic, story, other_domain_url, other_domain_url)
            assert(mediawords.tm.domains.skip_self_linked_domain(db, tl) is False)
