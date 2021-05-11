import abc
import dataclasses
from typing import Optional

import pytest

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_download_for_feed
from mediawords.util.web.user_agent import UserAgent

from crawler_fetcher.config import CrawlerConfig
from crawler_fetcher.engine import handler_for_download
from crawler_fetcher.exceptions import McCrawlerFetcherHardError
from crawler_fetcher.handlers.feed_univision import DownloadFeedUnivisionHandler


@dataclasses.dataclass
class UnivisionTestCredentials(object):
    """Univision test credentials to be used for testing."""
    url: str
    client_id: str
    client_secret: str


class AbstractUnivisionTest(object, metaclass=abc.ABCMeta):
    __slots__ = [
        'db',
    ]

    @classmethod
    @abc.abstractmethod
    def univision_credentials(cls) -> Optional[UnivisionTestCredentials]:
        """Return test credentials to test Univision integration with, or None if you'd like the tests to be skipped."""
        raise NotImplementedError("Abstract method")

    @classmethod
    @abc.abstractmethod
    def expect_to_find_some_stories(cls) -> bool:
        """If True, we should expect to find some stories in the downloaded feed."""
        raise NotImplementedError("Abstract method")

    @classmethod
    def _mock_crawler_config(cls) -> CrawlerConfig:
        credentials = cls.univision_credentials()

        class MockCrawlerConfig(CrawlerConfig):

            @staticmethod
            def univision_client_id() -> Optional[str]:
                return credentials.client_id

            @staticmethod
            def univision_client_secret() -> Optional[str]:
                return credentials.client_secret

        return MockCrawlerConfig()

    # noinspection PyPep8Naming
    def setUp(self) -> None:
        self.db = connect_to_db()

    # noinspection PyMethodMayBeStatic
    def test_api_request_signature(self):
        # Invalid inputs:

        # Empty input
        with pytest.raises(McCrawlerFetcherHardError):
            # noinspection PyTypeChecker
            DownloadFeedUnivisionHandler._api_request_url_with_signature(
                api_url=None,
                client_id=None,
                client_secret=None,
            )

        # Invalid URL
        with pytest.raises(McCrawlerFetcherHardError):
            DownloadFeedUnivisionHandler._api_request_url_with_signature(
                api_url='ftp://',
                client_id='client_id',
                client_secret='secret_key',
            )

        # URL with "client_id"
        with pytest.raises(McCrawlerFetcherHardError):
            DownloadFeedUnivisionHandler._api_request_url_with_signature(
                api_url='http://www.test.com/?client_id=a',
                client_id='client_id',
                client_secret='secret_key',
            )

        # Sanitization and query parameter sorting
        assert DownloadFeedUnivisionHandler._api_request_url_with_signature(
            api_url='http://www.test.com/',  # with slash
            client_id='client_id',
            client_secret='client_secret',
        ) == DownloadFeedUnivisionHandler._api_request_url_with_signature(
            api_url='http://www.test.com',  # without slash
            client_id='client_id',
            client_secret='client_secret',
        ), 'With and without ending slash'

        assert 'a=a&b=a&b=b&c=a&c=b&c=c' in DownloadFeedUnivisionHandler._api_request_url_with_signature(
            api_url='http://www.test.com/?c=c&c=b&c=a&b=b&b=a&a=a',
            client_id='client_id',
            client_secret='client_secret',
        ), 'Sorted query parameters'

    def test_api_request(self):
        """Make an API request, see if it succeeds."""

        credentials = self.univision_credentials()

        handler = DownloadFeedUnivisionHandler(crawler_config=self._mock_crawler_config())
        api_request_url = handler._api_request_url_with_signature_from_config(api_url=credentials.url)
        assert api_request_url, 'API request URL is not empty'

        ua = UserAgent()
        ua.set_timeout(30)

        response = ua.get(api_request_url)
        assert response.is_success(), 'API request was successful'

        json_string = response.decoded_content()
        assert json_string, 'JSON response is not empty'

        json = response.decoded_json()
        assert json.get('status', None) == 'success', "JSON response was successful"
        assert 'data' in json, 'JSON response has "data" key'

    def test_fetch_handle_download(self):
        credentials = self.univision_credentials()

        medium = self.db.create(table='media', insert_hash={
            'name': f"Media for test feed {credentials.url}",
            'url': 'http://www.univision.com/',
        })

        feed = self.db.create(table='feeds', insert_hash={
            'name': 'feed',
            'type': 'univision',
            'url': credentials.url,
            'media_id': medium['media_id'],
        })

        download = create_download_for_feed(db=self.db, feed=feed)

        handler = handler_for_download(db=self.db, download=download)
        assert isinstance(handler, DownloadFeedUnivisionHandler)

        # Recreate handler with mock configuration
        handler = DownloadFeedUnivisionHandler(crawler_config=self._mock_crawler_config())

        response = handler.fetch_download(db=self.db, download=download)
        assert response

        handler.store_response(db=self.db, download=download, response=response)

        download = self.db.find_by_id(table='downloads', object_id=download['downloads_id'])
        assert download
        assert download['state'] == 'success', f"Download's state is not 'success': {download['state']}"
        assert not download['error_message'], f"Download's error_message should be empty: {download['error_message']}"

        if self.expect_to_find_some_stories():
            story_downloads = self.db.query("""
                SELECT *
                FROM downloads
                WHERE feeds_id = %(feeds_id)s
                  AND type = 'content'
                  AND state = 'pending'
            """, {
                'feeds_id': download['feeds_id'],
            }).hashes()
            assert story_downloads, 'One or more story downloads were derived from feed'
