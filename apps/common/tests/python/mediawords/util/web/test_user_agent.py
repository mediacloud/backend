import os
import re
import tempfile
import time
from http import HTTPStatus
from typing import Union
from unittest import TestCase
from urllib.parse import quote, parse_qs

import pytest
from furl import furl

from mediawords.test.hash_server import HashServer
from mediawords.util.compress import gzip, gunzip
from mediawords.util.config.common import UserAgentConfig, AuthenticatedDomain
from mediawords.util.parse_json import encode_json, decode_json
from mediawords.util.log import create_logger
from mediawords.util.network import random_unused_port
from mediawords.util.text import random_string
from mediawords.util.url import urls_are_equal
from mediawords.util.web.user_agent import (
    UserAgent,
    McUserAgentException,
    McGetFollowHTTPHTMLRedirectsException,
    McParallelGetException,
)
from mediawords.util.web.user_agent.request.request import Request, McUserAgentRequestException

log = create_logger(__name__)


class TestUserAgentTestCase(TestCase):
    """UserAgent test case."""

    __slots__ = [
        # Random port used for testing
        '__test_port',

        # Base URL used for testing
        '__test_url',
    ]

    def setUp(self):
        self.__test_port = random_unused_port()
        self.__test_url = 'http://localhost:%d' % self.__test_port

    def test_get(self):
        """Basic GET."""

        # Undefined URL
        with pytest.raises(McUserAgentException):
            ua = UserAgent()
            # noinspection PyTypeChecker
            ua.get(url=None)

        # Non-HTTP(S) URL
        with pytest.raises(McUserAgentException):
            ua = UserAgent()
            ua.get(url='gopher://gopher.floodgap.com/0/v2/vstat')

        # URL with invalid IDNA
        with pytest.raises(McUserAgentException):
            ua = UserAgent()
            ua.get('http://michigan-state-football-sexual-assault-charges-arrest-players-names')

        pages = {'/test': 'Hello!', }
        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/test' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == 'Hello!'

    def test_get_utf8_url(self):
        """Basic GET with UTF-8 URL."""

        pages = {'/šiaurė': 'pietūs', }
        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/šiaurė' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == 'pietūs'

    def test_get_big_file(self):
        """Basic GET with 1 MB file (exceeding the chunk size)."""

        test_content_length = 1024 * 1024
        test_content = random_string(length=test_content_length)

        pages = {'/test': test_content, }
        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/test' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == test_content

    def test_get_user_agent_from_headers(self):
        """User-Agent: and From: headers."""

        def __callback_user_agent_from_headers(request: HashServer.Request) -> Union[str, bytes]:
            r = ""
            r += "HTTP/1.0 200 OK\r\n"
            r += "Content-Type: application/json; charset=UTF-8\r\n"
            r += "\r\n"
            r += encode_json({
                'user-agent': request.header('User-Agent'),
                'from': request.header('From'),
            })
            return r

        pages = {
            '/user-agent-from-headers': {
                'callback': __callback_user_agent_from_headers,
            }
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/user-agent-from-headers' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)

        expected_user_agent = 'mediacloud bot for open academic research (http://mediacloud.org)'
        expected_from = 'info@mediacloud.org'

        decoded_json = decode_json(response.decoded_content())
        assert decoded_json == {
            'user-agent': expected_user_agent,
            'from': expected_from,
        }

    def test_get_not_found(self):
        """Nonexistent pages."""

        def __callback_not_found(_: HashServer.Request) -> Union[str, bytes]:
            r = ""
            r += "HTTP/1.0 404 Not Found\r\n"
            r += "Content-Type: text/html; charset=UTF-8\r\n"
            r += "\r\n"
            r += "I do not exist."
            return r

        pages = {
            '/does-not-exist': {
                'callback': __callback_not_found,
            }
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/does-not-exist' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is False
        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == 'I do not exist.'

    def test_get_timeout(self):
        """Timeouts."""

        def __callback_timeout(_: HashServer.Request) -> Union[str, bytes]:
            r = ""
            r += "HTTP/1.0 404 200 OK\r\n"
            r += "Content-Type: text/html; charset=UTF-8\r\n"
            r += "\r\n"
            r += "And now we wait"

            time.sleep(10)

            return r

        pages = {
            '/timeout': {
                'callback': __callback_timeout,
            }
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        ua.set_timeout(2)
        assert ua.timeout() == 2

        test_url = '%s/timeout' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is False
        assert response.error_is_client_side() is True

    def test_get_valid_utf8_content(self):
        """Valid UTF-8 content."""

        pages = {
            '/valid-utf-8': {
                'header': 'Content-Type: text/plain; charset=UTF-8',
                'content': '¡ollǝɥ',
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/valid-utf-8' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == '¡ollǝɥ'

    def test_get_valid_utf8_content_no_charset(self):
        """Valid UTF-8 content, no charset defined anywhere."""

        pages = {
            '/valid-utf-8-no-charset': {

                # Let's see if UA manages to guess the encoding
                'header': 'Content-Type: application/json',
                'content': "{'text': '¡ollǝɥ'}",
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/valid-utf-8-no-charset' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == "{'text': '¡ollǝɥ'}"

    def test_get_invalid_utf8_content(self):
        """Invalid UTF-8 content."""

        pages = {
            '/invalid-utf-8': {
                'header': 'Content-Type: text/plain; charset=UTF-8',
                'content': b"\xf0\x90\x28\xbc",
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/invalid-utf-8' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)

        # https://en.wikipedia.org/wiki/Specials_(Unicode_block)#Replacement_character
        replacement_character = "\uFFFD"

        expected_content = (
            "%(rc)s\x28%(rc)s" % {'rc': replacement_character},  # OS X
            "%(rc)s%(rc)s\x28%(rc)s" % {'rc': replacement_character}  # Ubuntu
        )
        assert response.decoded_content() in expected_content

    def test_get_non_utf8_content(self):
        """Non-UTF-8 content."""

        pages = {
            '/non-utf-8': {
                'header': 'Content-Type: text/plain; charset=iso-8859-13',
                'content': b"\xd0auk\xf0tai po piet\xf8.",
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/non-utf-8' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == 'Šaukštai po pietų.'

    def test_get_non_utf8_content_html(self):
        """Non-UTF-8 content where the content encoding is set in content and not the headers."""

        # Perl's Encode had issues with GB2312, so let's see what requests has to offer
        pages = {
            '/non-utf-8-html': {

                # No encoding in HTTP headers
                'header': 'Content-Type: text/html',

                # Encoding in HTML data's <meta> element
                'content': b"""
                <html>
                <head>
                    <title>\xca\xb1\xd5\xfe\x2d\x2d\xc8\xcb\xc3\xf1\xcd\xf8</title>
                    <meta http-equiv="content-type" content="text/html;charset=GB2312"/>
                </head>
                <body>
                </body>
                </html>
                """,
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/non-utf-8-html' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert '时政--人民网' in response.decoded_content()

    def test_get_non_utf8_content_no_charset(self):
        """Valid non-UTF-8 content, no charset defined anywhere."""

        pages = {
            '/valid-non-utf-8-no-charset': {

                # Let's see if UA manages to guess the encoding
                'header': 'Content-Type: application/json',
                'content': b"{'text': '\xca\xb1\xd5\xfe\x2d\x2d\xc8\xcb\xc3\xf1\xcd\xf8'}",
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/valid-non-utf-8-no-charset' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == "{'text': '时政--人民网'}"

    def test_get_non_utf8_invalid_charset(self):
        """Non-UTF-8 content with invalid encoding."""

        pages = {
            '/invalid-charset': {

                # No encoding in HTTP headers
                'header': 'Content-Type: text/html; charset=invalid-charset',

                # Encoding in HTML data's <meta> element
                'content': b"""
                <html>
                <head>
                    <title>Page with invalid charset</title>
                    <meta http-equiv="content-type" content="text/html;charset=invalid-charset"/>
                </head>
                <body>
                </body>
                </html>
                """,
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/invalid-charset' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)

    def test_get_big_file_no_charset(self):
        """Big file, no charset set."""

        test_content_length = 1024 * 1024 * 100  # 100 MB
        test_content = b"\xfe" * test_content_length

        pages = {
            '/big_file_no_charset': {

                'header': 'Content-Type: application/octet-stream',
                'content': test_content,
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/big_file_no_charset' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)

    def test_get_max_size_with_bogus_content_length_header(self):
        """Max. download size (with bogus Content-Length header)."""

        test_content_length = 1024 * 10
        test_content = random_string(length=test_content_length)

        pages = {
            '/max-download-side': {
                'header': 'Content-Length: kim-kardashian',
                'content': test_content,
            },
        }

        max_size = int(test_content_length / 10)

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        ua.set_max_size(max_size)
        assert ua.max_size() == max_size

        test_url = '%s/max-download-side' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        # LWP::UserAgent truncates the response but still reports it as successful
        assert response.is_success()
        assert len(response.decoded_content()) >= max_size
        assert len(response.decoded_content()) <= len(test_content)

    def test_get_max_size_without_content_length_header(self):
        """Max. download size (without Content-Length header)."""

        test_content_length = 1024 * 10
        test_content = random_string(length=test_content_length)

        pages = {
            '/max-download-side': test_content,
        }

        max_size = int(test_content_length / 10)

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        ua.set_max_size(max_size)
        assert ua.max_size() == max_size

        test_url = '%s/max-download-side' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        # LWP::UserAgent truncates the response but still reports it as successful
        assert response.is_success()
        assert len(response.decoded_content()) >= max_size
        assert len(response.decoded_content()) <= len(test_content)

    def test_get_max_size_unlimited(self):
        """Max. download size (without max. size being set)."""

        test_content_length = 1024 * 10
        test_content = random_string(length=test_content_length)

        pages = {
            '/max-download-side': test_content,
        }

        hs = HashServer(port=self.__test_port, pages=pages)

        # Test unlimited length responses
        hs.start()

        ua = UserAgent()
        ua.set_max_size(None)
        assert ua.max_size() is None

        test_url = '%s/max-download-side' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success()
        assert len(response.decoded_content()) == test_content_length

    def test_set_timeout(self):
        """Try to set timeout to various values (the actual timeout gets tested elsewhere)."""

        ua = UserAgent()

        ua.set_timeout(42)
        assert ua.timeout() == 42

        ua.set_timeout(None)
        assert ua.timeout() is None

    def test_get_max_redirect(self):
        """Max. redirects."""

        max_redirect = 3
        pages = {
            '/1': {'redirect': '/2'},
            '/2': {'redirect': '/3'},
            '/3': {'redirect': '/4'},
            '/4': {'redirect': '/5'},
            '/5': {'redirect': '/6'},
            '/6': {'redirect': '/7'},
            '/7': {'redirect': '/8'},
            '/8': "Shouldn't be able to get to this one.",
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        ua.set_max_redirect(max_redirect)
        assert ua.max_redirect() == max_redirect

        response = ua.get('%s/1' % self.__test_url)

        hs.stop()

        assert response.is_success() is False

        # Try setting to None
        ua.set_max_redirect(None)
        assert ua.max_redirect() is None

    def test_get_request_headers(self):
        """Set custom HTTP request headers."""

        def __callback_get_request_headers(request: HashServer.Request) -> Union[str, bytes]:
            none_header_is_defined = False
            if 'X-None-Header' in request.headers():
                none_header_is_defined = True

            r = ""
            r += "HTTP/1.0 200 OK\r\n"
            r += "Content-Type: application/json; charset=UTF-8\r\n"
            r += "\r\n"
            r += encode_json({
                'custom-header': request.header('X-Custom-Header'),
                'empty-header': request.header('X-Empty-Header'),
                'none-header-is-defined': none_header_is_defined,
            })
            return r

        pages = {
            '/test-custom-header': {
                'callback': __callback_get_request_headers,
            }
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/test-custom-header' % self.__test_url

        rq = Request(method='GET', url=test_url)
        rq.set_header(name='X-Custom-Header', value='foo')
        rq.set_header(name='X-Empty-Header', value='')
        with pytest.raises(McUserAgentRequestException):
            # noinspection PyTypeChecker
            rq.set_header(name='X-None-Header', value=None)

        response = ua.request(rq)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)

        decoded_json = decode_json(response.decoded_content())
        assert decoded_json == {
            'custom-header': 'foo',
            'empty-header': '',
            'none-header-is-defined': False,
        }

    def test_get_response_status(self):
        """HTTP status code and message."""

        def __callback_get_response_status(_: HashServer.Request) -> Union[str, bytes]:
            r = ""
            r += "HTTP/1.0 418 Jestem czajniczek\r\n"
            r += "Content-Type: text/html; charset=UTF-8\r\n"
            r += "\r\n"
            r += "☕"
            return r

        pages = {
            '/test': {
                'callback': __callback_get_response_status,
            }
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/test' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == '☕'

        assert response.code() == 418
        assert response.message() == 'Jestem czajniczek'
        assert response.status_line() == '418 Jestem czajniczek'

    def test_get_response_status_empty(self):
        """HTTP status code and empty message."""

        def __callback_get_response_status_empty(_: HashServer.Request) -> Union[str, bytes]:
            r = ""
            r += "HTTP/1.0 451\r\n"
            r += "Content-Type: text/html; charset=UTF-8\r\n"
            r += "\r\n"
            r += "👩‍⚖️"
            return r

        pages = {
            '/test': {
                'callback': __callback_get_response_status_empty,
            }
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/test' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == '👩‍⚖️'

        assert response.code() == 451
        assert response.message() == ''
        assert response.status_line() == '451'

    def test_get_response_headers(self):
        """Response's uppercase / lowercase headers."""

        pages = {
            '/test': {
                'header': (
                    "Content-Type: text/plain; charset=UTF-8\r\n"
                    "X-Empty-Header: \r\n"
                    "X-Media-Cloud: mediacloud"
                ),
                'content': "pnolɔ ɐıpǝɯ",
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/test' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == 'pnolɔ ɐıpǝɯ'

        assert response.header(name='X-Media-Cloud') == 'mediacloud'
        assert response.header(name='x-media-cloud') == 'mediacloud'

        assert response.header(name='X-Empty-Header') == ''
        assert response.header(name='x-empty-header') == ''

        assert response.header(name='x-nonexistent-header') is None

    def test_get_response_content_type(self):
        """Response's Content-Type."""

        pages = {
            '/test': {
                'header': "Content-Type: application/xhtml+xml; charset=UTF-8",
                'content': "pnolɔ ɐıpǝɯ",
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/test' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2=test_url)
        assert response.decoded_content() == 'pnolɔ ɐıpǝɯ'

        assert response.content_type() == 'application/xhtml+xml'

    def test_get_response_raw_data(self):
        """Raw data."""

        input_data = random_string(length=1024)
        input_compressed_data = gzip(input_data.encode('utf-8'))
        assert isinstance(input_compressed_data, bytes), "Random compressed data is supposed to be 'bytes'."

        pages = {
            '/raw-data': {
                'header': 'Content-Type: application/x-gzip',
                'content': input_compressed_data,
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        test_url = '%s/raw-data' % self.__test_url
        response = ua.get(test_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)

        output_compressed_data = response.raw_data()
        assert isinstance(output_compressed_data, bytes)

        assert output_compressed_data == input_compressed_data

        output_data = gunzip(output_compressed_data).decode('utf-8')
        assert output_data == input_data

    def test_get_blacklisted_url(self):
        """Blacklisted URLs."""

        tempdir = tempfile.mkdtemp()
        assert os.path.isdir(tempdir)

        whitelist_temp_file = os.path.join(tempdir, 'whitelisted_url_opened.txt')
        blacklist_temp_file = os.path.join(tempdir, 'blacklisted_url_opened.txt')
        assert os.path.exists(whitelist_temp_file) is False
        assert os.path.exists(blacklist_temp_file) is False

        def __callback_whitelist(_: HashServer.Request) -> Union[str, bytes]:
            with open(whitelist_temp_file, 'w') as f:
                f.write("Whitelisted URL has been fetched.")

            r = ""
            r += "HTTP/1.0 200 OK\r\n"
            r += "Content-Type: text/plain\r\n"
            r += "\r\n"
            r += "Whitelisted page (should be fetched)."
            return r

        def __callback_blacklist(_: HashServer.Request) -> Union[str, bytes]:
            with open(blacklist_temp_file, 'w') as f:
                f.write("Blacklisted URL has been fetched.")

            r = ""
            r += "HTTP/1.0 200 OK\r\n"
            r += "Content-Type: text/plain\r\n"
            r += "\r\n"
            r += "Blacklisted page (should not be fetched)."
            return r

        pages = {
            '/whitelisted': {'callback': __callback_whitelist},
            '/blacklisted': {'callback': __callback_blacklist},
        }

        whitelisted_url = '%s/whitelisted' % self.__test_url
        blacklisted_url = '%s/blacklisted' % self.__test_url

        class UserAgentBlacklistedConfig(UserAgentConfig):

            @staticmethod
            def blacklist_url_pattern():
                return re.compile(re.escape(blacklisted_url))

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent(user_agent_config=UserAgentBlacklistedConfig())
        blacklisted_response = ua.get(blacklisted_url)
        whitelisted_response = ua.get(whitelisted_url)

        hs.stop()

        assert blacklisted_response.is_success() is False
        assert blacklisted_response.error_is_client_side() is True
        assert blacklisted_response.request().url() != blacklisted_url

        assert whitelisted_response.is_success() is True
        assert urls_are_equal(url1=whitelisted_response.request().url(), url2=whitelisted_url)

        assert os.path.isfile(whitelist_temp_file) is True
        assert os.path.isfile(blacklist_temp_file) is False

    def test_get_http_auth(self):
        """HTTP authentication."""

        pages = {
            '/auth': {
                'auth': 'username1:password2',
                'content': 'Authenticated!',
            }
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        base_auth_url = '%s/auth' % self.__test_url

        # No auth
        no_auth_response = ua.get(base_auth_url)
        assert no_auth_response.is_success() is False
        assert no_auth_response.code() == HTTPStatus.UNAUTHORIZED.value

        # Invalid auth in URL
        invalid_auth_url = 'http://incorrect_username1:incorrect_password2@localhost:%d/auth' % self.__test_port
        invalid_auth_response = ua.get(invalid_auth_url)
        assert invalid_auth_response.is_success() is False
        assert invalid_auth_response.code() == HTTPStatus.UNAUTHORIZED.value

        # Valid auth in URL
        valid_auth_url = 'http://username1:password2@localhost:%d/auth' % self.__test_port
        valid_auth_response = ua.get(valid_auth_url)
        assert valid_auth_response.is_success() is True
        assert valid_auth_response.code() == HTTPStatus.OK.value
        assert valid_auth_response.decoded_content() == 'Authenticated!'

        # Invalid auth in request
        invalid_auth_request = Request(method='GET', url=base_auth_url)
        invalid_auth_request.set_authorization_basic(username='incorrect_username1', password='incorrect_password2')
        invalid_auth_response = ua.request(invalid_auth_request)
        assert invalid_auth_response.is_success() is False
        assert invalid_auth_response.code() == HTTPStatus.UNAUTHORIZED.value

        # Valid auth in request
        valid_auth_request = Request(method='GET', url=base_auth_url)
        valid_auth_request.set_authorization_basic(username='username1', password='password2')
        valid_auth_response = ua.request(valid_auth_request)
        assert valid_auth_response.is_success() is True
        assert valid_auth_response.code() == HTTPStatus.OK.value
        assert valid_auth_response.decoded_content() == 'Authenticated!'

        hs.stop()

    def test_get_request_invalid_url(self):
        """request() with invalid IDNA URL."""
        with pytest.raises(McUserAgentRequestException):
            Request(method='GET', url='http://michigan-state-football-sexual-assault-charges-arrest-players-names')

    def test_get_authenticated_domains(self):
        """Authenticated domains (configured in mediawords.yml)."""

        # This is what get_url_distinctive_domain() returns for whatever reason
        domain = 'localhost.localhost'
        username = 'username1'
        password = 'password2'

        pages = {
            '/auth': {
                'auth': "%s:%s" % (username, password,),
                'content': 'Authenticated!',
            },
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        base_auth_url = '%s/auth' % self.__test_url

        class UserAgentNoAuthConfig(UserAgentConfig):
            @staticmethod
            def authenticated_domains():
                # No domains
                return []

        ua = UserAgent(user_agent_config=UserAgentNoAuthConfig())
        no_auth_response = ua.get(base_auth_url)
        assert no_auth_response.is_success() is False
        assert no_auth_response.code() == HTTPStatus.UNAUTHORIZED.value

        class UserAgentInvalidAuthConfig(UserAgentConfig):
            @staticmethod
            def authenticated_domains():
                # Invalid auth
                return [
                    AuthenticatedDomain(
                        domain=domain,
                        username='incorrect_username1',
                        password='incorrect_password2',
                    )
                ]

        ua = UserAgent(user_agent_config=UserAgentInvalidAuthConfig())
        invalid_auth_response = ua.get(base_auth_url)
        assert invalid_auth_response.is_success() is False
        assert invalid_auth_response.code() == HTTPStatus.UNAUTHORIZED.value

        class UserAgentValidAuthConfig(UserAgentConfig):
            @staticmethod
            def authenticated_domains():
                # Valid auth
                return [
                    AuthenticatedDomain(
                        domain=domain,
                        username=username,
                        password=password,
                    )
                ]

        ua = UserAgent(user_agent_config=UserAgentValidAuthConfig())
        valid_auth_response = ua.get(base_auth_url)
        assert valid_auth_response.is_success() is True
        assert valid_auth_response.code() == HTTPStatus.OK.value
        assert valid_auth_response.decoded_content() == 'Authenticated!'

        hs.stop()

    def test_get_follow_http_html_redirects_http(self):
        """HTTP redirects."""

        ua = UserAgent()

        with pytest.raises(McGetFollowHTTPHTMLRedirectsException):
            # noinspection PyTypeChecker
            ua.get_follow_http_html_redirects(url=None)

        with pytest.raises(McGetFollowHTTPHTMLRedirectsException):
            # noinspection PyTypeChecker
            ua.get_follow_http_html_redirects(url='gopher://gopher.floodgap.com/0/v2/vstat')

        # HTTP redirects
        pages = {
            '/first': {
                'redirect': '/second',
                'http_status_code': HTTPStatus.MOVED_PERMANENTLY.value,
            },
            '/second': {
                'redirect': '%s/third' % self.__test_url,
                'http_status_code': HTTPStatus.FOUND.value,
            },
            '/third': {
                'redirect': '/fourth',
                'http_status_code': HTTPStatus.SEE_OTHER.value,
            },
            '/fourth': {
                'redirect': '%s/fifth' % self.__test_url,
                'http_status_code': HTTPStatus.TEMPORARY_REDIRECT.value,
            },
            '/fifth': 'Seems to be working.',
        }

        starting_url = '%s/first' % self.__test_url

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        response = ua.get_follow_http_html_redirects(starting_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2='%s/fifth' % self.__test_url)
        assert response.decoded_content() == pages['/fifth']

    def test_get_follow_http_html_redirects_nonexistent(self):
        """HTTP redirects with the starting URL nonexistent."""

        # Nonexistent URL ("/first")
        pages = {}

        starting_url = '%s/first' % self.__test_url

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        response = ua.get_follow_http_html_redirects(starting_url)

        hs.stop()

        assert response.is_success() is False
        assert urls_are_equal(url1=response.request().url(), url2=starting_url)  # URL after unsuccessful HTTP redirects

    def test_get_follow_http_html_redirects_html(self):
        """HTML redirects."""

        pages = {
            '/first': '<meta http-equiv="refresh" content="0; URL=/second" />',
            '/second': '<meta http-equiv="refresh" content="url=third" />',
            '/third': '<META HTTP-EQUIV="REFRESH" CONTENT="10; URL=/fourth" />',
            '/fourth': '< meta content="url=fifth" http-equiv="refresh" >',
            '/fifth': 'Seems to be working too.',
        }

        starting_url = '%s/first' % self.__test_url

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        response = ua.get_follow_http_html_redirects(starting_url)

        hs.stop()

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2='%s/fifth' % self.__test_url)
        assert response.decoded_content() == pages['/fifth']

    def test_get_follow_http_html_redirects_http_loop(self):
        """HTTP redirects that end up in a loop."""

        starting_url = '%s/first' % self.__test_url

        # "http://127.0.0.1:9998/third?url=http%3A%2F%2F127.0.0.1%2Fsecond"
        third = '/third?url=%s' % quote('%s/second' % self.__test_url)

        pages = {
            # e.g. http://rss.nytimes.com/c/34625/f/640350/s/3a08a24a/sc/1/l/0L0Snytimes0N0C20A140C0A50C0A40Cus0C
            # politics0Cobama0Ewhite0Ehouse0Ecorrespondents0Edinner0Bhtml0Dpartner0Frss0Gemc0Frss/story01.htm
            '/first': {'redirect': '/second', 'http_status_code': HTTPStatus.SEE_OTHER.value},

            # e.g. http://www.nytimes.com/2014/05/04/us/politics/obama-white-house-correspondents-dinner.html?partner=
            # rss&emc=rss
            '/second': {'redirect': third, 'http_status_code': HTTPStatus.SEE_OTHER.value},

            # e.g. http://www.nytimes.com/glogin?URI=http%3A%2F%2Fwww.nytimes.com%2F2014%2F05%2F04%2Fus%2Fpolitics%2F
            # obama-white-house-correspondents-dinner.html%3Fpartner%3Drss%26emc%3Drss
            '/third': {'redirect': '/second', 'http_status_code': HTTPStatus.SEE_OTHER.value},
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        response = ua.get_follow_http_html_redirects(starting_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2='%s/second' % self.__test_url)

    def test_get_follow_http_html_redirects_html_loop(self):
        """HTML redirects that end up in a loop."""

        starting_url = '%s/first' % self.__test_url

        pages = {
            '/first': '<meta http-equiv="refresh" content="0; URL=/second" />',
            '/second': '<meta http-equiv="refresh" content="0; URL=/third" />',
            '/third': '<meta http-equiv="refresh" content="0; URL=/second" />',
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        response = ua.get_follow_http_html_redirects(starting_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2='%s/first' % self.__test_url)

    def test_get_follow_http_html_redirects_cookies(self):
        """Test if the method acts nicely when the server decides to ensure that the client supports cookies (e.g.
        http://www.dailytelegraph.com.au/news/world/charlie-hebdo-attack-police-close-in-on-two-armed-massacre-suspects-
        as-manhunt-continues-across-france/story-fni0xs63-1227178925700)"""

        starting_url = '%s/first' % self.__test_url
        test_content = 'This is the content.'

        cookie_name = "test_cookie"
        cookie_value = "I'm a cookie and I know it!"
        default_header = "Content-Type: text/html; charset=UTF-8\r\n"

        def __callback_first(request: HashServer.Request) -> Union[str, bytes]:
            cookies = request.cookies()
            r = ''

            if cookie_name in cookies and cookies[cookie_name] == cookie_value:
                log.debug("Cookie was set previously, showing page")

                r += "HTTP/1.0 200 OK\r\n"
                r += default_header
                r += "\r\n"
                r += test_content

            else:

                log.debug("Setting cookie, redirecting to /check_cookie")
                r += "HTTP/1.0 302 Moved Temporarily\r\n"
                r += default_header
                r += "Location: /check_cookie\r\n"
                r += "Set-Cookie: %s=%s\r\n" % (cookie_name, cookie_value,)
                r += "\r\n"
                r += "Redirecting to the cookie check page..."

            return r

        def __callback_check_cookie(request: HashServer.Request) -> Union[str, bytes]:
            cookies = request.cookies()
            r = ''

            if cookie_name in cookies and cookies[cookie_name] == cookie_value:
                log.debug("Cookie was set previously, redirecting back to the initial page")

                r += "HTTP/1.0 302 Moved Temporarily\r\n"
                r += default_header
                r += "Location: %s\r\n" % starting_url
                r += "\r\n"
                r += "Cookie looks fine, redirecting you back to the article..."

            else:
                log.debug("Cookie wasn't found, redirecting you to the /no_cookies page...")

                r += "HTTP/1.0 302 Moved Temporarily\r\n"
                r += default_header
                r += "Location: /no_cookies\r\n"
                r += "\r\n"
                r += 'Cookie wasn\'t found, redirecting you to the "no cookies" page...'

            return r

        pages = {
            '/first': {'callback': __callback_first},
            '/check_cookie': {'callback': __callback_check_cookie},
            '/no_cookies': "No cookie support, go away, we don\'t like you.",
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        response = ua.get_follow_http_html_redirects(starting_url)

        hs.stop()

        assert urls_are_equal(url1=response.request().url(), url2=starting_url)
        assert response.decoded_content() == test_content

    def test_get_follow_http_html_redirects_previous_responses(self):
        """previous() of Request object."""

        # FIXME probably belongs in a Request unit test

        def __page_http_redirect(page: str) -> dict:
            return {
                'redirect': page,
                'http_status_code': HTTPStatus.MOVED_PERMANENTLY.value,
            }

        def __page_html_redirect(page: str) -> str:
            return "<meta http-equiv='refresh' content='0; URL=%s' />" % page

        # Various types of redirects mixed together to test setting previous()
        pages = {
            '/page_1': __page_http_redirect('/page_2'),
            '/page_2': __page_html_redirect('/page_3'),
            '/page_3': __page_http_redirect('/page_4'),
            '/page_4': __page_http_redirect('/page_5'),
            '/page_5': __page_html_redirect('/page_6'),
            '/page_6': __page_html_redirect('/page_7'),

            # Final page
            '/page_7': 'Finally!',
        }

        starting_url = '%s/page_1' % self.__test_url

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        response = ua.get_follow_http_html_redirects(starting_url)

        hs.stop()

        assert response.is_success() is True
        assert response.decoded_content() == 'Finally!'
        assert urls_are_equal(url1=response.request().url(), url2='%s/page_7' % self.__test_url)

        # Test original_request()
        assert response.original_request() is not None
        assert urls_are_equal(url1=response.original_request().url(), url2='%s/page_1' % self.__test_url)

        # Test previous()
        # FIXME optimize into some sort of a loop
        response = response.previous()
        assert response is not None
        assert response.request() is not None
        assert urls_are_equal(url1=response.request().url(), url2='%s/page_6' % self.__test_url)

        response = response.previous()
        assert response is not None
        assert response.request() is not None
        assert urls_are_equal(url1=response.request().url(), url2='%s/page_5' % self.__test_url)

        response = response.previous()
        assert response is not None
        assert response.request() is not None
        assert urls_are_equal(url1=response.request().url(), url2='%s/page_4' % self.__test_url)

        response = response.previous()
        assert response is not None
        assert response.request() is not None
        assert urls_are_equal(url1=response.request().url(), url2='%s/page_3' % self.__test_url)

        response = response.previous()
        assert response is not None
        assert response.request() is not None
        assert urls_are_equal(url1=response.request().url(), url2='%s/page_2' % self.__test_url)

        response = response.previous()
        assert response is not None
        assert response.request() is not None
        assert urls_are_equal(url1=response.request().url(), url2='%s/page_1' % self.__test_url)

        assert response.previous() is None

    def test_get_follow_http_html_redirects_invalid_http_redirect_url(self):
        """HTML redirects with invalid URL in HTTP redirect."""

        pages = {
            '/first': {
                # Parsing this URL with requests / furl fails with:
                #
                #     UnicodeError: label empty or too long
                #
                'redirect': 'http://michigan-state-football-sexual-assault-charges-arrest-players-names.com',

                'http_status_code': HTTPStatus.MOVED_PERMANENTLY.value,
            },
        }

        starting_url = '%s/first' % self.__test_url

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        response = ua.get_follow_http_html_redirects(starting_url)

        hs.stop()

        assert response.is_success() is False
        assert urls_are_equal(url1=response.request().url(), url2='%s/first' % self.__test_url)
        assert "encoding with 'idna' codec failed" in response.decoded_content()

    def test_parallel_get(self):
        """parallel_get()."""

        def __callback_timeout(_: HashServer.Request) -> Union[str, bytes]:
            r = ''
            r += "HTTP/1.0 200 OK\r\n"
            r += "Content-Type: text/html; charset=UTF-8\r\n"
            r += "\r\n"
            r += "And now we wait"

            time.sleep(10)

            return r

        pages = {
            # Test UTF-8 while we're at it
            '/a': '𝘛𝘩𝘪𝘴 𝘪𝘴 𝘱𝘢𝘨𝘦 𝘈.',
            '/b': '𝕿𝖍𝖎𝖘 𝖎𝖘 𝖕𝖆𝖌𝖊 𝕭.',
            '/c': '𝕋𝕙𝕚𝕤 𝕚𝕤 𝕡𝕒𝕘𝕖 ℂ.',
            '/timeout': {'callback': __callback_timeout},
        }

        class UserAgentTimeoutFasterConfig(UserAgentConfig):
            @staticmethod
            def parallel_get_timeout():
                return 2  # time out faster

        urls = [
            '%s/a' % self.__test_url,
            '%s/b' % self.__test_url,
            '%s/c' % self.__test_url,
            '%s/timeout' % self.__test_url,  # times out
            '%s/does-not-exist' % self.__test_url,  # 404 Not Found
        ]

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent(user_agent_config=UserAgentTimeoutFasterConfig())

        responses = ua.parallel_get(urls)

        hs.stop()

        assert responses is not None
        assert len(responses) == len(urls)

        # Test order (which some code relies on)
        assert responses[0].request().url().endswith('/a')
        assert responses[1].request().url().endswith('/b')
        assert responses[2].request().url().endswith('/c')
        assert responses[3].request().url().endswith('/timeout')
        assert responses[4].request().url().endswith('/does-not-exist')

        path_responses = {}
        for response in responses:
            uri = furl(response.request().url())
            path = str(uri.path)
            path_responses[path] = response

        assert '/a' in path_responses
        assert path_responses['/a'].is_success() is True
        assert path_responses['/a'].decoded_content() == pages['/a']

        assert '/b' in path_responses
        assert path_responses['/b'].is_success() is True
        assert path_responses['/b'].decoded_content() == pages['/b']

        assert '/c' in path_responses
        assert path_responses['/c'].is_success() is True
        assert path_responses['/c'].decoded_content() == pages['/c']

        assert '/does-not-exist' in path_responses
        assert path_responses['/does-not-exist'].is_success() is False
        assert path_responses['/does-not-exist'].code() == HTTPStatus.NOT_FOUND.value

        assert '/timeout' in path_responses
        assert path_responses['/timeout'].is_success() is False
        assert path_responses['/timeout'].code() == HTTPStatus.REQUEST_TIMEOUT.value

    def test_parallel_get_invalid_urls(self):
        """parallel_get() with some / all invalid URLs."""

        urls = [
            'http://localhost/a',
            'badger',  # One invalid URL
        ]

        with pytest.raises(McParallelGetException):
            ua = UserAgent()
            ua.parallel_get(urls)

    def test_parallel_get_many_urls(self):
        """parallel_get() with many URLs (the number of which exceeds default web_store_num_parallel)."""

        page_count = 40

        pages = {}
        urls = []
        for x in range(page_count):
            pages['/page-%02d' % x] = 'Page %02d.' % x
            urls.append('%s/page-%02d' % (self.__test_url, x,))

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        responses = ua.parallel_get(urls)

        hs.stop()

        assert responses is not None
        assert len(responses) == len(urls)

        # Test order
        for x in range(page_count):
            response = responses[x]

            assert response.is_success()
            assert response.request().url().endswith('/page-%02d' % x)
            assert response.decoded_content() == 'Page %02d.' % x

    def test_parallel_get_duplicate_removal(self):
        """parallel_get() with duplicate URLs."""

        pages = {
            '/a': 'A.',
            '/b': 'B.',
            '/c': 'C.',
        }

        # "/c", "/a", "/b" is the expected order
        urls = [
            '%s/c' % self.__test_url,
            '%s/a' % self.__test_url,
            '%s/c' % self.__test_url,  # duplicate
            '%s/b' % self.__test_url,
            '%s/b' % self.__test_url,  # duplicate
            '%s/c' % self.__test_url,  # duplicate
        ]

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        responses = ua.parallel_get(urls)

        hs.stop()

        assert responses is not None
        assert len(responses) == 3
        assert responses[0].request().url().endswith('/c')
        assert responses[1].request().url().endswith('/a')
        assert responses[2].request().url().endswith('/b')

    def test_determined_retries(self):
        """Determined retries."""

        # We'll use temporary file for inter-process communication because callback
        # will be run in a separate fork so won't be able to modify variable on
        # main process
        f = tempfile.NamedTemporaryFile(mode='w', delete=False)
        f.write('0')
        f.close()
        request_count_filename = f.name

        def __callback_temporarily_buggy_page(_: HashServer.Request) -> Union[str, bytes]:
            """Page that doesn't work the first two times."""

            r = ''

            with open(request_count_filename, 'r+') as temp:
                temporarily_buggy_page_request_count = int(temp.readline().strip())
                temporarily_buggy_page_request_count += 1
                temp.seek(0)
                temp.write(str(temporarily_buggy_page_request_count))

            if temporarily_buggy_page_request_count < 3:
                log.debug("Simulating failure for %d time..." % temporarily_buggy_page_request_count)
                r += "HTTP/1.0 500 Internal Server Error\r\n"
                r += "Content-Type: text/plain\r\n"
                r += "\r\n"
                r += "something's wrong"

            else:
                log.debug("Returning successful request...")
                r += "HTTP/1.0 200 OK\r\n"
                r += "Content-Type: text/plain\r\n"
                r += "\r\n"
                r += "success on request %d" % temporarily_buggy_page_request_count

            return r

        def __callback_permanently_buggy_page(_: HashServer.Request) -> Union[str, bytes]:
            """Page that doesn't work at all."""

            r = ''
            r += "HTTP/1.0 500 Internal Server Error\r\n"
            r += "Content-Type: text/plain\r\n"
            r += "\r\n"
            r += "something's wrong"

            return r

        pages = {
            '/temporarily-buggy-page': {'callback': __callback_temporarily_buggy_page},
            '/permanently-buggy-page': {'callback': __callback_permanently_buggy_page},
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()
        ua.set_timeout(2)  # time-out really fast

        # Try disabling retries
        ua.set_timing(None)
        assert ua.timing() is None

        # Reenable timing
        ua.set_timing([1, 2, 4])
        assert ua.timing() == [1, 2, 4]

        response = ua.get('%s/temporarily-buggy-page' % self.__test_url)
        assert response.is_success() is True
        assert response.decoded_content() == 'success on request 3'

        response = ua.get('%s/permanently-buggy-page' % self.__test_url)
        assert response.is_success() is False

        hs.stop()

    def test_get_string(self):
        """get_string() method."""

        pages = {
            '/exists': 'I do exist.',
            # '/does-not-exist': None,
        }

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        exists_string = ua.get_string('%s/exists' % self.__test_url)
        does_not_exist_string = ua.get_string('%s/does-not-exist' % self.__test_url)

        hs.stop()

        assert exists_string == 'I do exist.'
        assert does_not_exist_string is None

    def test_post(self):
        """POST request."""

        def __callback_post(rq: HashServer.Request) -> Union[str, bytes]:
            r = ''
            r += "HTTP/1.0 200 OK\r\n"
            r += "Content-Type: application/json; charset=UTF-8\r\n"
            r += "\r\n"
            r += encode_json({
                'method': rq.method(),
                'content-type': rq.content_type(),
                'content': parse_qs(rq.content()),
            })

            return r

        pages = {
            '/test-post': {'callback': __callback_post},
        }
        test_url = '%s/test-post' % self.__test_url

        hs = HashServer(port=self.__test_port, pages=pages)
        hs.start()

        ua = UserAgent()

        # UTF-8 string request
        request = Request(method='POST', url=test_url)
        request.set_content_type('application/x-www-form-urlencoded; charset=utf-8')
        request.set_content('ą=č&ė=ž')

        response = ua.request(request)

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)

        decoded_json = decode_json(response.decoded_content())
        assert decoded_json == {
            'method': 'POST',
            'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
            'content': {
                'ą': ['č'],  # parse_qs() returns a list with a single item
                'ė': ['ž'],
            },
        }

        # UTF-8 dictionary request
        request = Request(method='POST', url=test_url)
        request.set_content_type('application/x-www-form-urlencoded; charset=utf-8')
        request.set_content({
            'ą': 'č',
            'ė': 'ž',
        })

        response = ua.request(request)

        assert response.is_success() is True
        assert urls_are_equal(url1=response.request().url(), url2=test_url)

        decoded_json = decode_json(response.decoded_content())
        assert decoded_json == {
            'method': 'POST',
            'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
            'content': {
                'ą': ['č'],  # parse_qs() returns a list with a single item
                'ė': ['ž'],
            },
        }

        hs.stop()
