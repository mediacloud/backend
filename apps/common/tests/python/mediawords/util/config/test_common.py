import pytest

from mediawords.util.config.common import (
    _authenticated_domains_from_json,
    AuthenticatedDomain,
    McConfigAuthenticatedDomainsException,
)


def test_authenticated_domains_from_json():
    # noinspection PyTypeChecker
    assert _authenticated_domains_from_json(None) == []
    assert _authenticated_domains_from_json('') == []
    assert _authenticated_domains_from_json('  ') == []

    assert _authenticated_domains_from_json("""
        [
            {"domain": "domain", "username": "user", "password": "pass"}
        ]
    """) == [
        AuthenticatedDomain(domain='domain', username='user', password='pass'),
    ]
    assert _authenticated_domains_from_json("""
        [
            {"domain": "domain", "username": "user", "password": "pass"},
            {"domain": "domain2", "username": "user2", "password": "pass2"}
        ]
    """) == [
        AuthenticatedDomain(domain='domain', username='user', password='pass'),
        AuthenticatedDomain(domain='domain2', username='user2', password='pass2'),
    ]

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # Invalid JSON
        _authenticated_domains_from_json('blergh')

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # No domain
        _authenticated_domains_from_json("""
            [
                {"username": "user", "password": "pass"}
            ]
        """)

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # No password
        _authenticated_domains_from_json("""
            [
                {"domain": "domain", "username": "user"}
            ]
        """)

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # List within a list
        _authenticated_domains_from_json("""
            [
                [
                    {"domain": "domain", "username": "user", "password": "pass"}
                ]
            ]
        """)

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # Just a dictionary without a list
        _authenticated_domains_from_json("""
            {"domain": "domain", "username": "user", "password": "pass"}
        """)

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # Single quotes instead of double ones (invalid JSON)
        _authenticated_domains_from_json("""
            [
                {'domain': 'domain', 'username': 'user', 'password': 'pass'}
            ]
        """)
