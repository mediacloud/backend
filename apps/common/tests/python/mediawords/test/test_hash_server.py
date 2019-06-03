import json
import socket
import time
from typing import Union

import pytest
import requests
from requests_futures.sessions import FuturesSession

from mediawords.util.network import random_unused_port, tcp_port_is_open
from mediawords.util.url import urls_are_equal
from mediawords.test.hash_server import (
    HashServer,
    HTTPStatus,
    McHashServerException,
    START_RANDOM_PORT,
    _fqdn,
)


def test_http_hash_server():
    port = random_unused_port()
    base_url = 'http://localhost:%d' % port

    def __simple_callback(request: HashServer.Request) -> Union[str, bytes]:
        r = ""
        r += "HTTP/1.0 200 OK\r\n"
        r += "Content-Type: application/json; charset=UTF-8\r\n"
        r += "\r\n"
        r += json.dumps({
            'name': 'callback',
            'method': request.method(),
            'url': request.url(),
            'content-type': request.content_type(),
            'params': request.query_params(),
            'cookies': request.cookies(),
        })
        return str.encode(r)

    # noinspection PyUnusedLocal
    def __callback_cookie_redirect(request: HashServer.Request) -> str:
        r = ""
        r += "HTTP/1.0 302 Moved Temporarily\r\n"
        r += "Content-Type: text/html; charset=UTF-8\r\n"
        r += "Location: /check_cookie\r\n"
        r += "Set-Cookie: test_cookie=I'm a cookie and I know it!\r\n"
        r += "\r\n"
        r += "Redirecting to the cookie check page..."
        return r

    def __callback_post(request: HashServer.Request) -> Union[str, bytes]:
        r = ""
        r += "HTTP/1.0 200 OK\r\n"
        r += "Content-Type: application/json; charset=UTF-8\r\n"
        r += "\r\n"
        r += json.dumps({
            'name': 'callback_post',
            'post_data': request.content(),
        })
        return str.encode(r)

    pages = {
        '/': 'home',
        '/foo': b'foo',
        '/bar': 'bar ąą',
        '/foo-bar': {b'redirect': b'/bar'},
        '/localhost': {'redirect': "http://localhost:%d/" % port},
        b'/127-foo': {b'redirect': "http://127.0.0.1:%d/foo" % port},
        '/auth': {b'auth': b'foo:bar', b'content': b"foo bar \xf0\x90\x28\xbc"},
        '/404': {b'content': b'not found', b'http_status_code': 404},
        '/callback': {b'callback': __simple_callback},

        # Test setting cookies, redirects
        '/callback_cookie_redirect': {'callback': __callback_cookie_redirect},

        # POST data
        '/callback_post': {'callback': __callback_post},
    }

    hs = HashServer(port=port, pages=pages)
    assert hs

    hs.start()

    assert tcp_port_is_open(port=port)

    assert str(requests.get('%s/' % base_url).text) == 'home'
    assert str(requests.get('%s/foo' % base_url).text) == 'foo'
    assert str(requests.get('%s/bar' % base_url).text) == 'bar ąą'
    assert str(requests.get('%s/foo-bar' % base_url).text) == 'bar ąą'
    assert str(requests.get('%s/localhost' % base_url).text) == 'home'
    assert str(requests.get('%s/127-foo' % base_url).text) == 'foo'

    # Path normalization
    assert str(requests.get('%s//' % base_url).text) == 'home'
    assert str(requests.get('%s///' % base_url).text) == 'home'
    assert str(requests.get('%s/something/../' % base_url).text) == 'home'
    assert str(requests.get('%s/something/..//' % base_url).text) == 'home'
    assert str(requests.get('%s/something/..///' % base_url).text) == 'home'
    assert str(requests.get('%s/foo/' % base_url).text) == 'foo'
    assert str(requests.get('%s/foo//' % base_url).text) == 'foo'
    assert str(requests.get('%s/foo///' % base_url).text) == 'foo'
    assert str(requests.get('%s/foo' % base_url).text) == 'foo'
    assert str(requests.get('%s/bar/../foo' % base_url).text) == 'foo'
    assert str(requests.get('%s/bar/../foo/' % base_url).text) == 'foo'
    assert str(requests.get('%s/bar/../foo//' % base_url).text) == 'foo'
    assert str(requests.get('%s/bar/../foo///' % base_url).text) == 'foo'

    response_json = requests.get('%s/callback?a=b&c=d' % base_url, cookies={'cookie_name': 'cookie_value'}).json()
    assert response_json == {
        'name': 'callback',
        'method': 'GET',
        'url': 'http://%s:%d/callback?a=b&c=d' % (_fqdn(), port),
        'content-type': None,
        'params': {
            'a': 'b',
            'c': 'd',
        },
        'cookies': {
            'cookie_name': 'cookie_value',
        },
    }

    response = requests.get('%s/callback_cookie_redirect' % base_url, allow_redirects=False)
    assert response.status_code == 302
    assert response.headers['Location'] == '/check_cookie'

    response = requests.get("%s/404" % base_url)
    assert response.status_code == HTTPStatus.NOT_FOUND.value
    assert 'Not Found' in response.reason

    auth_url = "%s/auth" % base_url

    assert requests.get(auth_url).status_code == HTTPStatus.UNAUTHORIZED
    assert requests.get(auth_url, auth=('foo', 'foo')).status_code == HTTPStatus.UNAUTHORIZED

    response = requests.get(auth_url, auth=('foo', 'bar'))
    assert response.status_code == HTTPStatus.OK
    assert response.content == b"foo bar \xf0\x90\x28\xbc"

    assert urls_are_equal(url1=hs.page_url('/callback?a=b&c=d'), url2='http://%s:%d/callback' % (_fqdn(), port))
    with pytest.raises(McHashServerException):
        hs.page_url('/does-not-exist')

    response_json = requests.post('%s/callback_post' % base_url, data='abc=def').json()
    assert response_json == {
        'name': 'callback_post',
        'post_data': 'abc=def',
    }

    hs.stop()


def test_http_hash_server_stop():
    """Test if HTTP hash server gets stopped properly (including children)."""
    port = random_unused_port()
    base_url = 'http://localhost:%d' % port

    # noinspection PyTypeChecker,PyUnusedLocal
    def __callback_sleep_forever(request: HashServer.Request) -> Union[str, bytes]:
        time.sleep(9999)

    pages = {
        '/simple-page': 'Works!',
        '/sleep-forever': {'callback': __callback_sleep_forever},
    }

    hs = HashServer(port=port, pages=pages)
    assert hs

    hs.start()

    assert tcp_port_is_open(port=port)

    request_timed_out = False
    try:
        requests.get('%s/sleep-forever' % base_url, timeout=1)
    except requests.exceptions.Timeout:
        request_timed_out = True
    assert request_timed_out is True

    assert str(requests.get('%s/simple-page' % base_url).text) == 'Works!'

    # Restart the server with the same port, make sure it works again, i.e. the server gets stopped properly, kills all
    # its children and releases the port
    hs.stop()

    assert tcp_port_is_open(port=port) is False

    hs = HashServer(port=port, pages=pages)
    assert hs

    hs.start()

    assert tcp_port_is_open(port=port) is True

    assert str(requests.get('%s/simple-page' % base_url).text) == 'Works!'

    hs.stop()


def test_http_hash_server_multiple_servers():
    """Test running multiple hash servers at the same time."""

    port_1 = random_unused_port()
    port_2 = random_unused_port()

    base_url_1 = 'http://localhost:%d' % port_1
    base_url_2 = 'http://localhost:%d' % port_2

    # noinspection PyTypeChecker,PyUnusedLocal
    def __callback_sleep_forever(request: HashServer.Request) -> Union[str, bytes]:
        time.sleep(9999)

    pages = {
        '/simple-page': 'Works!',
        '/sleep-forever': {'callback': __callback_sleep_forever},
    }

    hs_1 = HashServer(port=port_1, pages=pages)
    hs_2 = HashServer(port=port_2, pages=pages)

    assert hs_1
    assert hs_2

    hs_1.start()
    hs_2.start()

    assert tcp_port_is_open(port=port_1)
    assert tcp_port_is_open(port=port_2)

    for base_url in [base_url_1, base_url_2]:
        request_timed_out = False
        try:
            requests.get('%s/sleep-forever' % base_url, timeout=1)
        except requests.exceptions.Timeout:
            request_timed_out = True
        assert request_timed_out is True

        assert str(requests.get('%s/simple-page' % base_url).text) == 'Works!'

    hs_1.stop()
    hs_2.stop()

    assert tcp_port_is_open(port=port_1) is False
    assert tcp_port_is_open(port=port_2) is False


# noinspection PyUnresolvedReferences
def test_http_hash_server_multiple_clients():
    """Test running hash server with multiple clients."""

    port = random_unused_port()

    # noinspection PyTypeChecker,PyUnusedLocal
    def __callback_timeout(request: HashServer.Request) -> Union[str, bytes]:
        r = ""
        r += "HTTP/1.0 200 OK\r\n"
        r += "Content-Type: text/html; charset=UTF-8\r\n"
        r += "\r\n"
        r += "And now we wait"
        time.sleep(10)
        return str.encode(r)

    pages = {
        '/a': '𝘛𝘩𝘪𝘴 𝘪𝘴 𝘱𝘢𝘨𝘦 𝘈.',
        '/timeout': {'callback': __callback_timeout},
        # '/does-not-exist': '404',
        '/b': '𝕿𝖍𝖎𝖘 𝖎𝖘 𝖕𝖆𝖌𝖊 𝕭.',
        '/c': '𝕋𝕙𝕚𝕤 𝕚𝕤 𝕡𝕒𝕘𝕖 ℂ.',
    }

    hs = HashServer(port=port, pages=pages)
    assert hs

    hs.start()

    assert tcp_port_is_open(port=port)

    base_url = 'http://localhost:%d' % port

    session = FuturesSession(max_workers=10)

    future_a = session.get('%s/a' % base_url, timeout=2)
    future_timeout = session.get('%s/timeout' % base_url, timeout=2)
    future_404 = session.get('%s/does-not-exist' % base_url, timeout=2)
    future_b = session.get('%s/b' % base_url, timeout=2)
    future_c = session.get('%s/c' % base_url, timeout=2)

    response_a = future_a.result()

    with pytest.raises(requests.Timeout):
        future_timeout.result()

    response_404 = future_404.result()
    response_b = future_b.result()
    response_c = future_c.result()

    assert response_b.status_code == 200
    assert response_b.text == '𝕿𝖍𝖎𝖘 𝖎𝖘 𝖕𝖆𝖌𝖊 𝕭.'

    assert response_c.status_code == 200
    assert response_c.text == '𝕋𝕙𝕚𝕤 𝕚𝕤 𝕡𝕒𝕘𝕖 ℂ.'

    assert response_404.status_code == 404

    assert response_a.status_code == 200
    assert response_a.text == '𝘛𝘩𝘪𝘴 𝘪𝘴 𝘱𝘢𝘨𝘦 𝘈.'

    hs.stop()


def test_random_port() -> None:
    """Test assigning a random port where port = 0."""

    hss = []
    for i in range(3):
        hs = HashServer(port=0, pages={'/foo': 'bar'})
        assert hs is not None

        hs.start()

        assert hs.port() >= START_RANDOM_PORT
        assert tcp_port_is_open(hs.port())
        assert str(requests.get(hs.page_url('/foo')).text) == 'bar'
        hss.append(hs)

    [hs.stop() for hs in hss]


def test_start_delay() -> None:
    """Test the delay= parameter to hs.start."""
    hs = HashServer(port=0, pages={'/foo': 'bar'})

    hs.start(delay=1)
    caught_exception = False
    try:
        requests.get(hs.page_url('/foo'))
    except requests.exceptions.ConnectionError:
        caught_exception = True

    assert caught_exception

    time.sleep(2)
    assert str(requests.get(hs.page_url('/foo')).text) == 'bar'

    hs.stop()


def __hostname_resolves(hostname: str) -> bool:
    try:
        socket.gethostbyname(hostname)
        return True
    except socket.error:
        return False


def test_fqdn():
    fq_hostname = _fqdn()
    assert fq_hostname != ''
    assert __hostname_resolves(fq_hostname) is True
