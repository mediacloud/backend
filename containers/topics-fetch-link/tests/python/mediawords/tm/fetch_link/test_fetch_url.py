#!/usr/bin/env py.test

from mediawords.db import connect_to_db
from mediawords.test.hash_server import HashServer
# noinspection PyProtectedMember
from mediawords.tm.fetch_link import _fetch_url


def test_fetch_url():
    db = connect_to_db()

    def _meta_redirect(r):
        resp = ""
        resp += 'HTTP/1.0 200 OK\r\n'
        resp += 'Content-Type: text/html\r\n\r\n'
        resp += '<meta http-equiv="refresh" content="0; url=%s-foo">\n' % r.url()
        return resp

    hs = HashServer(
        port=0,
        pages={
            '/foo': 'bar',
            '/400': {'http_status_code': 400},
            '/404': {'http_status_code': 404},
            '/500': {'http_status_code': 500},
            '/mr-foo': 'meta redirect target',
            '/mr': {'callback': _meta_redirect},
        })

    hs.start(delay=2)

    port = hs.port()

    timeout_args = {
        'network_down_host': 'localhost',
        'network_down_port': port,
        'network_down_timeout': 1,
        'domain_timeout': 0
    }

    # before delayed start, 404s and 500s should still return None
    assert not _fetch_url(db, hs.page_url('/404'), **timeout_args).is_success
    assert not _fetch_url(db, hs.page_url('/500'), **timeout_args).is_success

    # request for a valid page should make the call wait until the hs comes up
    assert _fetch_url(db, hs.page_url('/foo'), **timeout_args).content == 'bar'

    # and now a 400 should return a None
    assert not _fetch_url(db, hs.page_url('/400'), **timeout_args).is_success

    # make sure invalid url does not raise an exception
    assert not _fetch_url(db, 'this is not a url', **timeout_args) is None

    # make sure that requests follow meta redirects
    response = _fetch_url(db, hs.page_url('/mr'), **timeout_args)

    assert response.content == 'meta redirect target'
    assert response.last_requested_url == hs.page_url('/mr-foo')
