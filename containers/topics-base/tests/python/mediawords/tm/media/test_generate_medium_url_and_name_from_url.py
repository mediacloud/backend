#!/usr/bin/env py.test

from mediawords.tm.media import generate_medium_url_and_name_from_url


def test_generate_medium_url_and_name_from_url() -> None:
    (url, name) = generate_medium_url_and_name_from_url('http://foo.com/bar')
    assert url == 'http://foo.com/'
    assert name == 'foo.com'
