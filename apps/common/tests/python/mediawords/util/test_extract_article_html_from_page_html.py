import multiprocessing
from typing import Union
from unittest import TestCase

from mediawords.test.hash_server import HashServer
from mediawords.util.config.common import CommonConfig
from mediawords.util.extract_article_from_page import extract_article_html_from_page_html
from mediawords.util.network import random_unused_port
from mediawords.util.parse_json import encode_json


def test_extract_article_html_from_page_html():
    """Basic test."""

    content = """
    <html>
    <head>
    <title>I'm a test</title>
    </head>
    <body>
    <p>Hi test, I'm dad!</p>
    </body>
    </html>        
    """

    response = extract_article_html_from_page_html(content=content)

    assert response
    assert 'extracted_html' in response
    assert 'extractor_version' in response

    assert "I'm a test" in response['extracted_html']
    assert "Hi test, I'm dad!" in response['extracted_html']
    assert 'readabilityBody' in response['extracted_html']  # <body id="readabilityBody">

    assert "readability-lxml" in response['extractor_version']


class TestExtractConnectionErrors(TestCase):
    """Extract the page but fail the first response."""

    __slots__ = [
        'is_first_response',
    ]

    expected_extracted_text = "Extraction worked the second time!"

    def __extract_but_initially_fail(self, _: HashServer.Request) -> Union[str, bytes]:
        """Page callback that fails initially but then changes its mind."""

        with self.is_first_response.get_lock():
            if self.is_first_response.value == 1:
                self.is_first_response.value = 0

                # Closest to a connection error that we can get
                raise Exception("Whoops!")

            else:
                response = ""
                response += "HTTP/1.0 200 OK\r\n"
                response += "Content-Type: application/json; charset=UTF-8\r\n"
                response += "\r\n"
                response += encode_json({
                    'extracted_html': self.expected_extracted_text,
                    'extractor_version': 'readability-lxml',
                })
                return response

    def test_extract_article_html_from_page_html_connection_errors(self):
        """Try extracting with connection errors."""

        # Use multiprocessing.Value() because request might be handled in a fork
        self.is_first_response = multiprocessing.Value('i', 1)

        pages = {
            '/extract': {
                'callback': self.__extract_but_initially_fail,
            }
        }
        port = random_unused_port()

        hs = HashServer(port=port, pages=pages)
        hs.start()

        class MockExtractorCommonConfig(CommonConfig):
            """Mock configuration which points to our unstable extractor."""

            def extractor_api_url(self) -> str:
                return f'http://localhost:{port}/extract'

        extractor_response = extract_article_html_from_page_html(content='whatever', config=MockExtractorCommonConfig())

        hs.stop()

        assert extractor_response
        assert 'extracted_html' in extractor_response
        assert 'extractor_version' in extractor_response

        assert extractor_response['extracted_html'] == self.expected_extracted_text

        assert not self.is_first_response.value, "Make sure the initial extractor call failed."
