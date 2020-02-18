import abc
import re
from typing import List

from mediawords.db import DatabaseHandler
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent import Response

from crawler_fetcher.exceptions import McCrawlerFetcherHardError
from crawler_fetcher.handler import AbstractDownloadHandler

log = create_logger(__name__)


class DefaultStoreMixin(AbstractDownloadHandler, metaclass=abc.ABCMeta):
    """
    Mix-in for download handlers which store download to the key-value store.

    The response handler filters out errors, passes the raw response data to the download handler and adds returned
    story IDs to the extraction queue. Download storage is being done in a specific download handler, not the response
    handler.
    """

    _MAX_5XX_RETRIES = 10
    """Max. number of times to try a page after a 5xx error."""

    @abc.abstractmethod
    def store_download(self, db: DatabaseHandler, download: dict, content: str) -> List[int]:
        """
        Postprocess and store a download that was just fetched.

        Returns a list of story IDs to be extracted, for example:

        * 'content' downloads return an arrayref with a single story ID for the content download;
        * 'feed/syndicated' downloads return an empty list because there's nothing to be extracted from a syndicated
          feed;
        * 'feed/web_page' downloads return a list with a single 'web_page' story to be extracted.
        """
        raise NotImplemented("Abstract method")

    def _store_failed_download_error_message(self, db: DatabaseHandler, download: dict, response: Response) -> None:
        """
        Deal with any errors returned by the fetcher response.

        If the error status looks like something that the site could recover from (503, 500 timeout), queue another time
        out using back off timing.  If we don't recognize the status as something we can recover from or if we have
        exceeded the max. retries, set the 'state' of the download to 'error' and set the 'error_messsage' to describe
        the error.
        """
        download = decode_object_from_bytes_if_needed(download)

        downloads_id = download['downloads_id']

        if response.is_success():
            # Hard error because only failed responses should reach this helper
            raise McCrawlerFetcherHardError("Download was successful, so nothing to handle")

        error_num = 1
        error = download.get('error_message', None)
        if error:
            error_num_match = re.search(r'\[error_num: (\d+)\]$', error)
            if error_num_match:
                error_num = int(error_num_match.group(1)) + 1
            else:
                error_num = 1

        error_message = f"{response.status_line()}\n[error_num: {error_num}]"

        responded_with_timeout = re.search(r'(503|500 read timeout)', response.status_line(), flags=re.IGNORECASE)
        if responded_with_timeout and error_num < self._MAX_5XX_RETRIES:
            db.query("""
                UPDATE downloads
                SET
                    state = 'pending',
                    download_time = NOW() + %(download_interval)s::interval,
                    error_message = %(error_message)s
                WHERE downloads_id = %(downloads_id)s
            """, {
                'download_interval': f"{error_num} hours",
                'error_message': error_message,
                'downloads_id': downloads_id,
            })

        else:
            db.query("""
                UPDATE downloads
                SET
                    state = 'error',
                    error_message = %(error_message)s
                WHERE downloads_id = %(downloads_id)s
            """, {
                'error_message': error_message,
                'downloads_id': downloads_id,
            })

    def store_response(self, db: DatabaseHandler, download: dict, response: Response) -> None:

        download = decode_object_from_bytes_if_needed(download)

        downloads_id = download['downloads_id']
        download_url = download['url']

        log.info(f"Handling download {downloads_id}...")
        log.debug(f"(URL of download {downloads_id} which is about to be handled: {download_url})")

        if not response.is_success():
            log.info(f"Download {downloads_id} errored: {response.decoded_content()}")
            self._store_failed_download_error_message(db=db, download=download, response=response)
            return

        supported_content_types_regex = re.compile(r'text|html|xml|rss|atom|application/json', flags=re.IGNORECASE)
        if re.search(supported_content_types_regex, response.content_type()):
            content = response.decoded_content()
        else:
            content = '(unsupported content type)'

        db.query("""
            UPDATE downloads
            SET url = %(download_url)s
            WHERE downloads_id = %(downloads_id)s
              AND url != %(download_url)s
        """, {
            'downloads_id': downloads_id,
            'download_url': download_url,
        })

        story_ids_to_extract = self.store_download(db=db, download=download, content=content)

        for stories_id in story_ids_to_extract:
            log.debug(f"Adding story {stories_id} for download {downloads_id} to extraction queue...")
            JobBroker(queue_name='MediaWords::Job::ExtractAndVector').add_to_queue(stories_id=stories_id)

        log.info(f"Handled download {downloads_id}...")
        log.debug(f"(URL of download {downloads_id} that was just handled: {download_url})")
