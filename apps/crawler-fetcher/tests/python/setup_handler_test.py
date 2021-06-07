import abc
from typing import Dict, Any, Optional
from unittest import TestCase

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_story_stack
from mediawords.test.hash_server import HashServer
from mediawords.util.network import random_unused_port

from crawler_fetcher.engine import handler_for_download


class TestDownloadHandler(TestCase, metaclass=abc.ABCMeta):
    __slots__ = [
        'db',
        'port',
        'media',
        'feed',

        '__hs',
    ]

    @abc.abstractmethod
    def hashserver_pages(self) -> Dict[str, Any]:
        """Return HashServer pages to serve."""
        raise NotImplementedError("Abstract method")

    def _fetch_and_handle_response(self, path: str, downloads_id: Optional[int] = None) -> Dict[str, Any]:
        """Call the fetcher and handler on the given URL. Return the download passed to the fetcher and handler."""

        if downloads_id:
            download = self.db.find_by_id(table='downloads', object_id=downloads_id)
        else:
            download = self.db.create(table='downloads', insert_hash={
                'url': f"http://localhost:{self.port}{path}",
                'host': 'localhost',
                'type': 'feed',
                'state': 'pending',
                'priority': 0,
                'sequence': 1,
                'feeds_id': self.feed['feeds_id'],
            })
            downloads_id = download['downloads_id']

        handler = handler_for_download(db=self.db, download=download)

        response = handler.fetch_download(db=self.db, download=download)
        assert response

        handler.store_response(db=self.db, download=download, response=response)

        download = self.db.find_by_id(table='downloads', object_id=downloads_id)

        return download

    def setUp(self) -> None:
        self.db = connect_to_db()

        self.port = random_unused_port()

        self.__hs = HashServer(port=self.port, pages=self.hashserver_pages())
        self.__hs.start()

        self.media = create_test_story_stack(db=self.db, data={'A': {'B': [1]}})
        self.feed = self.media['A']['feeds']['B']

    def tearDown(self) -> None:
        self.__hs.stop()
