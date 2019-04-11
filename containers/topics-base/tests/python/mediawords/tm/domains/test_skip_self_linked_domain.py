#!/usr/bin/env py.test

from mediawords.tm.domains import skip_self_linked_domain, MAX_SELF_LINKS
from mediawords.tm.domains.setup_test_domains import TestTMDomainsDB
from mediawords.util.url import get_url_distinctive_domain


class TestSkipSelfLinkedDomain(TestTMDomainsDB):
    """Run tests that require database access."""

    def test_skip_self_linked_domain(self) -> None:
        """Test skip_self_linked_domain."""

        # no topic_links_id should always return False
        assert (skip_self_linked_domain(self.db, {}) is False)

        # always skip search type pages
        story_domain = get_url_distinctive_domain(self.story['url'])
        regex_skipped_urls = ['http://%s/%s' % (story_domain, suffix) for suffix in ['search', 'author', 'tag']]
        for url in regex_skipped_urls:
            tl = self.create_topic_link(self.topic, self.story, url, url)
            assert (skip_self_linked_domain(self.db, tl) is True)

        self_domain_url = 'http://%s/foo/bar' % story_domain
        for i in range(MAX_SELF_LINKS - len(regex_skipped_urls) - 1):
            url = self_domain_url + str(i)
            tl = self.create_topic_link(self.topic, self.story, url, url)
            assert (skip_self_linked_domain(self.db, tl) is False)

        num_tested_skipped_urls = 10
        for i in range(num_tested_skipped_urls):
            tl = self.create_topic_link(self.topic, self.story, self_domain_url, self_domain_url)
            assert (skip_self_linked_domain(self.db, tl) is True)

        other_domain_url = 'http://other.domain/foo/bar'
        num_tested_other_urls = 10
        for i in range(num_tested_other_urls):
            tl = self.create_topic_link(self.topic, self.story, other_domain_url, other_domain_url)
            assert (skip_self_linked_domain(self.db, tl) is False)
