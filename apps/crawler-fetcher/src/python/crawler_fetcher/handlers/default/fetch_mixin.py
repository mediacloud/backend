import abc
from typing import Optional

from mediawords.db import DatabaseHandler
from mediawords.db.exceptions.handler import McTupleAlreadyMovedError
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import sql_now
from mediawords.util.url import is_http_url
from mediawords.util.web.user_agent import Response, UserAgent

from crawler_fetcher.handler import AbstractDownloadHandler
from crawler_fetcher.exceptions import McCrawlerFetcherSoftError

log = create_logger(__name__)


class DefaultFetchMixin(AbstractDownloadHandler, metaclass=abc.ABCMeta):
    """Mix-in to be used by download handlers which fetch the download using a simple UserAgent().get()."""

    # noinspection PyMethodMayBeStatic
    def _download_url(self, download: dict) -> str:
        """
        Given a download dict, return an URL that should bet fetched for the download.

        The default of what it does is trivial, but some subclasses might want to override this function to be able to
        adjust the download URL in some way.
        """
        return download['url']

    def fetch_download(self, db: DatabaseHandler, download: dict) -> Optional[Response]:
        download = decode_object_from_bytes_if_needed(download)

        url = self._download_url(download=download)
        if not is_http_url(url):
            raise McCrawlerFetcherSoftError(f"URL is not HTTP(s): {url}")

        download['download_time'] = sql_now()
        download['state'] = 'fetching'

        try:
            db.update_by_id(table='downloads', object_id=download['downloads_id'], update_hash=download)
        except McTupleAlreadyMovedError as ex:
            # Some attempts to set the download's row to "fetching" fail with:
            #
            #   "tuple to be locked was already moved to another partition due to concurrent update"
            #
            # If that happens, we assume that some other fetcher instance somehow got to the download first and do
            # nothing
            log.warning(f"Some other fetcher got to download {download['downloads_id']} first: {ex}")
            return None
        except Exception as ex:
            # Raise further on misc. errors
            raise ex

        ua = UserAgent()
        response = ua.get_follow_http_html_redirects(url)

        return response
