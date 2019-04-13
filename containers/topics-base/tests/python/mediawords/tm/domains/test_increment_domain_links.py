from mediawords.tm.domains.setup_test_domains import TestTMDomainsDB
from mediawords.util.url import get_url_distinctive_domain


class TestIncrementDomainLinks(TestTMDomainsDB):
    """Run tests that require database access."""

    def test_increment_domain_links(self) -> None:
        """Test incremeber_domain_links9()."""

        nomatch_domain = 'no.match'
        story_domain = get_url_distinctive_domain(self.story['url'])

        num_url_matches = 3
        for i in range(num_url_matches):
            self.create_topic_link(self.topic, self.story, story_domain, nomatch_domain)
            td = self.get_topic_domain(self.topic, nomatch_domain)

            assert (td is not None)
            assert (td['self_links'] == i + 1)

        num_redirect_matches = 3
        for i in range(num_redirect_matches):
            self.create_topic_link(self.topic, self.story, nomatch_domain, story_domain)
            td = self.get_topic_domain(self.topic, story_domain)

            assert (td is not None)
            assert (td['self_links'] == i + 1)
