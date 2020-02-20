import re
import time
from http import HTTPStatus
from typing import Dict, Any

from mediawords.util.sql import get_epoch_from_sql_date

from .setup_handler_test import TestDownloadHandler


class TestHandlerErrors(TestDownloadHandler):

    @classmethod
    def _sql_date_is_in_future(cls, date: str) -> bool:
        """Return True if a given SQL date is in the future."""
        epoch_date = get_epoch_from_sql_date(date=date)
        return epoch_date > time.time()

    def hashserver_pages(self) -> Dict[str, Any]:
        return {
            '/foo': '<rss version="2.0"><channel /></rss>',
            '/404': {'content': 'not found', 'http_status_code': HTTPStatus.NOT_FOUND.value},
            '/500': {'content': 'server error', 'http_status_code': HTTPStatus.INTERNAL_SERVER_ERROR.value},
            '/503': {'content': 'service unavailable', 'http_status_code': HTTPStatus.SERVICE_UNAVAILABLE.value},
        }

    def test_handler_errors(self):
        """Test that Handler::_handle_error() deals correctly with various types of responses."""

        download_foo = self._fetch_and_handle_response(path='/foo')
        assert download_foo['state'] == 'success', 'foo download state'

        download_404 = self._fetch_and_handle_response(path='/404')
        assert download_404['state'] == 'error', '404 download state'

        download_503 = self._fetch_and_handle_response(path='/503')
        assert download_503['state'] == 'pending', '503 download 1 state'
        assert self._sql_date_is_in_future(
            download_503['download_time']
        ), f"date '{download_503['date']}' from 503 download 1 should be in the future"

        for i in range(2, 10):
            download_503 = self._fetch_and_handle_response(path='/503', downloads_id=download_503['downloads_id'])
            assert download_503['state'] == 'pending', f'503 download {i} state'
            assert self._sql_date_is_in_future(
                download_503['download_time']
            ), f"date '{download_503['date']}' from 503 download {i} should be in the future"

            assert re.search(
                rf'\[error_num: {i}\]$',
                download_503['error_message'],
            ), f"503 download {i} error message includes error num"

        download_503 = self._fetch_and_handle_response(path='/503', downloads_id=download_503['downloads_id'])
        assert download_503['state'] == 'error', '503 final download state'
