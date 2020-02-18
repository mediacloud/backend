from typing import List

from mediawords.db import DatabaseHandler
from mediawords.dbi.downloads.store import store_content
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

from crawler_fetcher.exceptions import McCrawlerFetcherHardError
from crawler_fetcher.handler import AbstractDownloadHandler
from crawler_fetcher.handlers.default.fetch_mixin import DefaultFetchMixin
from crawler_fetcher.handlers.default.store_mixin import DefaultStoreMixin

log = create_logger(__name__)


class DownloadContentHandler(DefaultFetchMixin, DefaultStoreMixin, AbstractDownloadHandler):

    def store_download(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        download = decode_object_from_bytes_if_needed(download)
        content = decode_object_from_bytes_if_needed(content)

        downloads_id = download['downloads_id']
        stories_id = download['stories_id']

        if not downloads_id:
            raise McCrawlerFetcherHardError("'downloads_id' is empty.")

        if not stories_id:
            raise McCrawlerFetcherHardError("'stories_id' is empty.")

        if content is None:
            # Content might be empty but not None
            raise McCrawlerFetcherHardError(f"Content for download {downloads_id}, story {stories_id} is None.")

        log.info(f"Processing content download {downloads_id} (story {stories_id})...")

        if len(content) == 0:
            log.warning(f"Content for download {downloads_id}, story {stories_id} is empty.")

        download = store_content(db=db, download=download, content=content)

        log.info(f"Done processing content download {downloads_id} (story {stories_id})")

        story_ids_to_extract = [
            download['stories_id'],
        ]

        return story_ids_to_extract
