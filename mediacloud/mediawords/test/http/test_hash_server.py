import json
from nose.tools import assert_raises
import requests

from mediawords.util.network import random_unused_port
from mediawords.test.http.hash_server import *


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

    response_json = requests.get('%s/callback?a=b&c=d' % base_url, cookies={'cookie_name': 'cookie_value'}).json()
    assert response_json == {
        'name': 'callback',
        'method': 'GET',
        'url': 'http://localhost:%d/callback?a=b&c=d' % port,
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

    assert hs.page_url('/callback?a=b&c=d') == 'http://localhost:%d/callback' % port
    assert_raises(McHashServerException, hs.page_url, '/does-not-exist')

    response_json = requests.post('%s/callback_post' % base_url, data='abc=def').json()
    assert response_json == {
        'name': 'callback_post',
        'post_data': 'abc=def',
    }

    hs.stop()
