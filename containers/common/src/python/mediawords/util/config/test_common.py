import pytest

from mediawords.util.config.common import (
    _crawler_authenticated_domains_from_string,
    CrawlerAuthenticatedDomain,
    McConfigCrawlerAuthenticatedDomainsException,
)


def test_crawler_authenticated_domains_from_string():
    # noinspection PyTypeChecker
    assert _crawler_authenticated_domains_from_string(None) == []
    assert _crawler_authenticated_domains_from_string('') == []
    assert _crawler_authenticated_domains_from_string('user:pass@domain') == [
        CrawlerAuthenticatedDomain(domain='domain', username='user', password='pass'),
    ]
    assert _crawler_authenticated_domains_from_string('user:pass@domain;user2:pass2@domain2') == [
        CrawlerAuthenticatedDomain(domain='domain', username='user', password='pass'),
        CrawlerAuthenticatedDomain(domain='domain2', username='user2', password='pass2'),
    ]

    with pytest.raises(McConfigCrawlerAuthenticatedDomainsException):
        _crawler_authenticated_domains_from_string('blergh')

    with pytest.raises(McConfigCrawlerAuthenticatedDomainsException):
        _crawler_authenticated_domains_from_string('username:password')

    with pytest.raises(McConfigCrawlerAuthenticatedDomainsException):
        _crawler_authenticated_domains_from_string('username@domain')

    with pytest.raises(McConfigCrawlerAuthenticatedDomainsException):
        _crawler_authenticated_domains_from_string('username:password@domain;username')

    with pytest.raises(McConfigCrawlerAuthenticatedDomainsException):
        _crawler_authenticated_domains_from_string('username:password:password2@domain')

    with pytest.raises(McConfigCrawlerAuthenticatedDomainsException):
        _crawler_authenticated_domains_from_string('username:password@domain@domain2')
