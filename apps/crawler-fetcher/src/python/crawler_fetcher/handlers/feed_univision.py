import hashlib
from typing import List, Dict, Any

from crawler_fetcher.handlers.default.fetch_mixin import DefaultFetchMixin
from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads.store import get_media_id
from mediawords.util.log import create_logger
from mediawords.util.parse_json import decode_json
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import get_sql_date_from_epoch
from mediawords.util.url import is_http_url

from furl import furl

from crawler_fetcher.config import CrawlerConfig
from crawler_fetcher.exceptions import McCrawlerFetcherHardError, McCrawlerFetcherSoftError
from crawler_fetcher.handler import AbstractDownloadHandler
from crawler_fetcher.handlers.feed import AbstractDownloadFeedHandler
from crawler_fetcher.new_story import add_story_and_content_download
from crawler_fetcher.str2time import str2time_21st_century

log = create_logger(__name__)


class DownloadFeedUnivisionHandler(DefaultFetchMixin, AbstractDownloadFeedHandler, AbstractDownloadHandler):
    __slots__ = [
        '__crawler_config',
    ]

    def __init__(self, crawler_config: CrawlerConfig = None):
        if not crawler_config:
            crawler_config = CrawlerConfig()
        self.__crawler_config = crawler_config

    @classmethod
    def _api_request_url_with_signature(cls,
                                        api_url: str,
                                        client_id: str,
                                        client_secret: str,
                                        http_method: str = 'GET') -> str:
        """Return API URL with request signature appended."""

        api_url = decode_object_from_bytes_if_needed(api_url)
        client_id = decode_object_from_bytes_if_needed(client_id)
        client_secret = decode_object_from_bytes_if_needed(client_secret)
        http_method = decode_object_from_bytes_if_needed(http_method)

        if not (api_url and client_id and client_secret):
            raise McCrawlerFetcherHardError("One or more required parameters are unset.")

        if not is_http_url(api_url):
            raise McCrawlerFetcherHardError(f"API URL '{api_url}' is not a HTTP(S) URL")

        if not http_method:
            http_method = 'GET'

        http_method = http_method.upper()

        uri = furl(api_url)
        if uri.args.get('client_id', None):
            raise McCrawlerFetcherHardError("Query already contains 'client_id'.")

        uri.args.add('client_id', client_id)

        if not str(uri.path):
            # Set to slash if it's unset
            uri.path.segments = ['']

        # Sort query params as per API spec
        sorted_args = []
        for key in sorted(uri.args.keys()):
            values = uri.args.getlist(key)
            for value in sorted(values):
                sorted_args.append({key: value})

        uri.args.clear()
        for sorted_arg in sorted_args:
            key, value = sorted_arg.popitem()
            uri.args.add(key, value)

        log.debug(f"Sorted query params: {uri.args}")

        log.debug(f"URI: {str(uri)}")

        api_url_path = str(uri.path)
        api_url_query = str(uri.query)

        unhashed_secret_key = f"{http_method}{client_id}{api_url_path}?{api_url_query}{client_secret}"
        log.debug(f"Unhashed secret key: {unhashed_secret_key}")

        signature = hashlib.sha1(unhashed_secret_key.encode('utf-8')).hexdigest()
        log.debug(f"Signature (hashed secret key): {signature}")

        uri.args.add('signature', signature)
        log.debug(f"API request URL: {str(uri)}")

        return str(uri)

    def _api_request_url_with_signature_from_config(self, api_url: str, http_method: str = 'GET'):
        """Return API URL with request signature appended; Univision credentials are being read from configuration."""
        api_url = decode_object_from_bytes_if_needed(api_url)
        http_method = decode_object_from_bytes_if_needed(http_method)

        if not (self.__crawler_config.univision_client_id() and self.__crawler_config.univision_client_secret()):
            raise McCrawlerFetcherHardError("Univision credentials are unset.")

        return self._api_request_url_with_signature(
            api_url=api_url,
            client_id=self.__crawler_config.univision_client_id(),
            client_secret=self.__crawler_config.univision_client_secret(),
            http_method=http_method,
        )

    def _download_url(self, download: dict) -> str:
        url = download['url']

        # Return URL with Univision's credentials
        url_with_credentials = self._api_request_url_with_signature_from_config(api_url=url)

        return url_with_credentials

    @classmethod
    def _get_stories_from_univision_feed(cls, content: str, media_id: int) -> List[Dict[str, Any]]:
        """Parse the feed. Return a (non-db-backed) story dict for each story found in the feed."""
        content = decode_object_from_bytes_if_needed(content)
        if isinstance(media_id, bytes):
            media_id = decode_object_from_bytes_if_needed(media_id)

        media_id = int(media_id)

        if not content:
            raise McCrawlerFetcherSoftError("Feed content is empty or undefined.")

        try:
            feed_json = decode_json(content)
        except Exception as ex:
            raise McCrawlerFetcherSoftError(f"Unable to decode Univision feed JSON: {ex}")

        try:
            # Intentionally raise exception on KeyError:
            if not feed_json['status'] == 'success':
                raise McCrawlerFetcherSoftError(f"Univision feed response is not 'success': {content}")
        except Exception as ex:
            raise McCrawlerFetcherSoftError(f"Unable to verify Univision feed status: {ex}")

        try:
            # Intentionally raise exception on KeyError:
            feed_items = feed_json.get('data', None).get('items', None)
        except Exception as ex:
            raise McCrawlerFetcherSoftError(f"Univision feed response does not have 'data'/'items' key: {ex}")

        stories = []

        for item in feed_items:
            url = item.get('url', None)
            if not url:
                # Some items in the feed don't have their URLs set
                log.warning(f"'url' for item is not set: {item}")
                continue

            # sic -- we take "uid" (without "g") and call it "guid" (with "g")
            guid = item.get('uid', None)
            if not guid:
                raise McCrawlerFetcherSoftError(f"Item does not have its 'uid' set: {item}")

            title = item.get('title', '(no title)')
            description = item.get('description', '')

            try:
                # Intentionally raise exception on KeyError:
                str_publish_date = item['publishDate']
                publish_timestamp = str2time_21st_century(str_publish_date)
                publish_date = get_sql_date_from_epoch(publish_timestamp)
            except Exception as ex:
                # Die for good because Univision's dates should be pretty predictable
                raise McCrawlerFetcherSoftError(f"Unable to parse item's {item} publish date: {ex}")

            log.debug(f"Story found in Univision feed: URL '{url}', title '{title}', publish date '{publish_date}'")
            stories.append({
                'url': url,
                'guid': guid,
                'media_id': media_id,
                'publish_date': publish_date,
                'title': title,
                'description': description,
            })

        return stories

    def add_stories_from_feed(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:

        download = decode_object_from_bytes_if_needed(download)
        content = decode_object_from_bytes_if_needed(content)

        media_id = get_media_id(db=db, download=download)

        stories = self._get_stories_from_univision_feed(content=content, media_id=media_id)

        story_ids = []

        for story in stories:
            story = add_story_and_content_download(db=db, story=story, parent_download=download)
            if story:
                if story.get('is_new', None):
                    story_ids.append(story['stories_id'])

        return story_ids

    def return_stories_to_be_extracted_from_feed(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:

        # Univision feed itself is not a story of any sort, so nothing to extract (stories from this feed will be
        # extracted as 'content' downloads)
        return []
