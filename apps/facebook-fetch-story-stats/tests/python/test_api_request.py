import tempfile
from typing import Dict, Any, Union
from unittest import TestCase

import pytest

from mediawords.test.hash_server import HashServer
from mediawords.util.log import create_logger
from mediawords.util.network import random_unused_port
from mediawords.util.parse_json import encode_json

# noinspection PyProtectedMember
from facebook_fetch_story_stats import FacebookConfig, _api_request
from facebook_fetch_story_stats.exceptions import McFacebookHardFailureException

log = create_logger(__name__)


class MockAPIServer(object):
    __slots__ = [
        '__hs',
        '__port',
    ]

    def __init__(self, pages: Dict[str, Any]):
        self.__port = random_unused_port()
        self.__hs = HashServer(port=self.__port, pages=pages)
        self.__hs.start()

    def __del__(self):
        self.__hs.stop()

    def config(self) -> FacebookConfig:
        port = self.__port

        class MockFacebookConfig(FacebookConfig):
            @staticmethod
            def api_endpoint() -> str:
                return f'http://localhost:{port}/'

            @staticmethod
            def seconds_to_wait_between_retries() -> int:
                # Don't wait between retries
                return 0

        return MockFacebookConfig()


class TestAPIRequest(TestCase):

    def test_successful(self):
        """Test with successful response."""

        def __successful_response(_: HashServer.Request) -> Union[str, bytes]:
            r = ""
            r += "HTTP/1.0 200 OK\r\n"
            r += "Content-Type: application/json; charset=UTF-8\r\n"
            r += "\r\n"
            r += encode_json({
                'something': 'something',
            })
            return r

        server = MockAPIServer(
            pages={
                '/': {
                    'callback': __successful_response,
                }
            }
        )

        response = _api_request(node='', params={'a': 'b'}, config=server.config())
        assert isinstance(response, dict)
        assert 'something' in response

    def test_invalid_json(self):
        """Test with invalid JSON response."""

        def __invalid_json_response(_: HashServer.Request) -> Union[str, bytes]:
            r = ""
            r += "HTTP/1.0 200 OK\r\n"
            r += "Content-Type: application/json; charset=UTF-8\r\n"
            r += "\r\n"
            r += "{'blerhg'"
            return r

        server = MockAPIServer(
            pages={
                '/': {
                    'callback': __invalid_json_response,
                }
            }
        )

        with pytest.raises(McFacebookHardFailureException):
            _api_request(node='', params={'a': 'b'}, config=server.config())

    def test_retryable_temporary_error(self):
        """Test with retryable API error which goes away after a few retries."""

        # We'll use temporary file for inter-process communication because callback will be run in a separate fork so
        # won't be able to modify variable on main process
        f = tempfile.NamedTemporaryFile(mode='w', delete=False)
        f.write('0')
        f.close()
        request_count_filename = f.name

        def __retryable_temporary_error_response(_: HashServer.Request) -> Union[str, bytes]:

            with open(request_count_filename, 'r+') as temp:
                temporarily_buggy_page_request_count = int(temp.readline().strip())
                temporarily_buggy_page_request_count += 1
                temp.seek(0)
                temp.write(str(temporarily_buggy_page_request_count))

                r = ""

            if temporarily_buggy_page_request_count < 3:
                log.debug(f"Simulating failure for {temporarily_buggy_page_request_count} time...")
                r += "HTTP/1.0 500 Internal Server Error\r\n"
                r += "Content-Type: application/json; charset=UTF-8\r\n"
                r += "\r\n"
                r += encode_json({
                    'error': {
                        'code': 2,
                        'message': 'API Unknown',
                    },
                })

            else:
                log.debug("Returning successful request...")
                r += "HTTP/1.0 200 OK\r\n"
                r += "Content-Type: application/json; charset=UTF-8\r\n"
                r += "\r\n"
                r += encode_json({
                    'looks like': 'it worked this time',
                })

            return r

        server = MockAPIServer(
            pages={
                '/': {
                    'callback': __retryable_temporary_error_response,
                }
            }
        )

        response = _api_request(node='', params={'a': 'b'}, config=server.config())
        assert isinstance(response, dict)
        assert 'looks like' in response

    def test_retryable_permanent_error(self):
        """Test with retryable API error which doesn't go away."""

        def __retryable_permanent_error_response(_: HashServer.Request) -> Union[str, bytes]:
            r = ""
            r += "HTTP/1.0 500 Internal Server Error\r\n"
            r += "Content-Type: application/json; charset=UTF-8\r\n"
            r += "\r\n"
            r += encode_json({
                'error': {
                    'code': 2,
                    'message': 'API Unknown',
                },
            })
            return r

        server = MockAPIServer(
            pages={
                '/': {
                    'callback': __retryable_permanent_error_response,
                }
            }
        )

        response = _api_request(node='', params={'a': 'b'}, config=server.config())
        assert isinstance(response, dict)
        assert 'error' in response
