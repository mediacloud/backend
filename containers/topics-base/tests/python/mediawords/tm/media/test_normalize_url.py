#!/usr/bin/env py.test

# noinspection PyProtectedMember
from mediawords.tm.media import _normalize_url, MAX_URL_LENGTH


def test_normalize_url():
    """Test normalize_url()."""
    assert _normalize_url('http://www.foo.com/') == 'http://foo.com/'
    assert _normalize_url('http://foo.com') == 'http://foo.com/'
    assert _normalize_url('http://articles.foo.com/') == 'http://foo.com/'

    long_url = 'http://foo.com/' + ('x' * (1024 * 1024))
    assert len(_normalize_url(long_url)) == MAX_URL_LENGTH
