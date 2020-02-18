import abc

from mediawords.db import DatabaseHandler
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sql import sql_now
from mediawords.util.web.user_agent import Response, UserAgent

from crawler_fetcher.handler import AbstractDownloadHandler


class DefaultFetchMixin(AbstractDownloadHandler, metaclass=abc.ABCMeta):
    """Mix-in to be used by download handlers which fetch the download using a simple UserAgent().get()."""

    def fetch_download(self, db: DatabaseHandler, download: dict) -> Response:
        download = decode_object_from_bytes_if_needed(download)

        download['download_time'] = sql_now()
        download['state'] = 'fetching'

        db.update_by_id(table='downloads', object_id=download['downloads_id'], update_hash=download)

        ua = UserAgent()
        url = download['url']
        response = ua.get_follow_http_html_redirects(url)

        return response
