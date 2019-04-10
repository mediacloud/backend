#!/usr/bin/env py.test

import pytest

from mediawords.util.config.common import (
    _authenticated_domains_from_string,
    AuthenticatedDomain,
    McConfigAuthenticatedDomainsException,
)


def test_authenticated_domains_from_string():
    # noinspection PyTypeChecker
    assert _authenticated_domains_from_string(None) == []
    assert _authenticated_domains_from_string('') == []
    assert _authenticated_domains_from_string('user:pass@domain') == [
        AuthenticatedDomain(domain='domain', username='user', password='pass'),
    ]
    assert _authenticated_domains_from_string('user:pass@domain;user2:pass2@domain2') == [
        AuthenticatedDomain(domain='domain', username='user', password='pass'),
        AuthenticatedDomain(domain='domain2', username='user2', password='pass2'),
    ]

    with pytest.raises(McConfigAuthenticatedDomainsException):
        _authenticated_domains_from_string('blergh')

    with pytest.raises(McConfigAuthenticatedDomainsException):
        _authenticated_domains_from_string('username:password')

    with pytest.raises(McConfigAuthenticatedDomainsException):
        _authenticated_domains_from_string('username@domain')

    with pytest.raises(McConfigAuthenticatedDomainsException):
        _authenticated_domains_from_string('username:password@domain;username')

    with pytest.raises(McConfigAuthenticatedDomainsException):
        _authenticated_domains_from_string('username:password:password2@domain')

    with pytest.raises(McConfigAuthenticatedDomainsException):
        _authenticated_domains_from_string('username:password@domain@domain2')
