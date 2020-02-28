"""
Controls and coordinates the work of the crawler provider, fetchers, and handlers.

The crawler engine coordinates the work of a single crawler_fetcher process.  A crawler_fetcher sits in a polling
loop looking for new download_ids in queued_downloads and, when one is found, fetching and handling the given
download.
"""

import time
from typing import Optional

from mediawords.db import DatabaseHandler, connect_to_db
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

from crawler_fetcher.exceptions import McCrawlerFetcherHardError, McCrawlerFetcherSoftError
from crawler_fetcher.handler import AbstractDownloadHandler
from crawler_fetcher.handlers.content import DownloadContentHandler
from crawler_fetcher.handlers.feed_podcast import DownloadFeedPodcastHandler
from crawler_fetcher.handlers.feed_syndicated import DownloadFeedSyndicatedHandler
from crawler_fetcher.handlers.feed_univision import DownloadFeedUnivisionHandler
from crawler_fetcher.handlers.feed_web_page import DownloadFeedWebPageHandler
from crawler_fetcher.timer import Timer

log = create_logger(__name__)

_SLEEP_SECONDS_ON_NO_DOWNLOADS = 10
"""How many seconds to sleep when no downloads are in the queue."""


def handler_for_download(db: DatabaseHandler, download: dict) -> AbstractDownloadHandler:
    """Returns correct handler for download."""

    download = decode_object_from_bytes_if_needed(download)

    downloads_id = int(download['downloads_id'])
    download_type = download['type']

    if download_type == 'feed':
        feeds_id = int(download['feeds_id'])
        feed = db.find_by_id(table='feeds', object_id=feeds_id)
        feed_type = feed['type']

        if feed_type == 'syndicated':
            handler = DownloadFeedSyndicatedHandler()
        elif feed_type == 'web_page':
            handler = DownloadFeedWebPageHandler()
        elif feed_type == 'univision':
            handler = DownloadFeedUnivisionHandler()
        elif feed_type == 'podcast':
            handler = DownloadFeedPodcastHandler()
        else:
            # Unknown feed type is a hard error as we don't types that we don't know about to be there
            raise McCrawlerFetcherHardError(
                f"Unknown feed type '{feed_type}' for feed {feeds_id}, download {downloads_id}"
            )
    elif download_type == 'content':
        handler = DownloadContentHandler()
    else:
        # Unknown download type is a hard error as we don't types that we don't know about to be there
        raise McCrawlerFetcherHardError(
            f"Unknown download type '{download_type}' for download {downloads_id}"
        )

    return handler


def _fetch_and_handle_download(db: DatabaseHandler, download: dict, handler: AbstractDownloadHandler) -> None:
    download = decode_object_from_bytes_if_needed(download)
    if not download:
        raise McCrawlerFetcherHardError("Download is unset.")
    downloads_id = download.get('downloads_id', None)
    if not downloads_id:
        raise McCrawlerFetcherHardError(f"'downloads_id' is unset for download {download}")

    url = download['url']

    log.info(f"Fetch: {downloads_id} {url}...")

    fetch_timer = Timer('fetch').start()
    response = handler.fetch_download(db=db, download=download)
    fetch_timer.stop()

    store_timer = Timer('store').start()
    try:
        handler.store_response(db=db, download=download, response=response)
    except Exception as ex:
        log.error(f"Error in handle_response() for downloads_id {downloads_id} {url}: {ex}")
        raise ex
    store_timer.stop()

    log.info(f"Fetch done: {downloads_id} {url}")


def _log_download_error(db: DatabaseHandler, download: Optional[dict], error_message: str) -> None:
    if not download:
        log.warning(f"Error while getting download from queue: {error_message}")
        return

    log.warning(f"Error while fetching download {download['downloads_id']}: {error_message}")
    if download['state'] not in {'fetching', 'queued'}:
        downloads_id = download['downloads_id']

        download['state'] = 'error'
        download['error_message'] = error_message
        try:
            db.update_by_id(table='downloads', object_id=downloads_id, update_hash=download)
        except Exception as ex:
            # If we can't log the error in the database, that's really bad so a hard exception
            raise McCrawlerFetcherHardError((
                f"Unable to log download error for download {downloads_id} in the database; "
                f"download error: {error_message}; database error: {ex}"
            ))


def run_fetcher(no_daemon: bool = False) -> None:
    """Poll queued_downloads for new downloads and call fetch_and_handle_download()."""

    idle_timer = Timer('idle').start()

    while True:

        # Reconnect
        db = connect_to_db()

        download = None
        try:
            downloads_id = db.query("SELECT pop_queued_download()").flat()[0]
            if downloads_id:
                download = db.find_by_id(table='downloads', object_id=downloads_id)

                idle_timer.stop()

                if download['state'] != 'pending':
                    log.info(f"Skipping download {downloads_id} with state '{download['state']}'")
                    continue

                handler = handler_for_download(db=db, download=download)

                _fetch_and_handle_download(db=db, download=download, handler=handler)

                idle_timer.start()
            else:
                time.sleep(_SLEEP_SECONDS_ON_NO_DOWNLOADS)

        except McCrawlerFetcherSoftError as ex:
            # Soft errors get logged (if possible)
            _log_download_error(db=db, download=download, error_message=str(ex))

        except Exception as ex:
            # Hard errors and uncategorized errors both get logged (if possible) and passed up
            _log_download_error(db=db, download=download, error_message=str(ex))
            raise ex

        db.disconnect()

        if no_daemon:
            break
