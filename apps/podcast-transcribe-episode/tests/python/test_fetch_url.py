import os
import shutil
import tempfile
from typing import Union
from unittest import TestCase

# noinspection PyPackageRequirements
import pytest

from mediawords.test.hash_server import HashServer
from mediawords.util.network import random_unused_port

from podcast_transcribe_episode.exceptions import McPermanentError
from podcast_transcribe_episode.fetch_url import fetch_big_file


class TestFetchBigFile(TestCase):
    __slots__ = [
        '__mock_data',
        '__hs',
        '__url',
        '__temp_dir',
        '__dest_file',
    ]

    def setUp(self) -> None:
        super().setUp()

        self.__mock_data = os.urandom(1024 * 1024)

        # noinspection PyUnusedLocal
        def __mp3_callback(request: HashServer.Request) -> Union[str, bytes]:
            response = "".encode('utf-8')
            response += "HTTP/1.0 200 OK\r\n".encode('utf-8')
            response += "Content-Type: audio/mpeg\r\n".encode('utf-8')
            response += f"Content-Length: {len(self.__mock_data)}\r\n".encode('utf-8')
            response += "\r\n".encode('utf-8')
            response += self.__mock_data
            return response

        port = random_unused_port()
        pages = {
            '/test.mp3': {
                'callback': __mp3_callback,
            }
        }

        self.__hs = HashServer(port=port, pages=pages)
        self.__hs.start()

        self.__url = f"http://127.0.0.1:{port}/test.mp3"

        self.__temp_dir = tempfile.mkdtemp('test')
        self.__dest_file = os.path.join(self.__temp_dir, 'test.mp3')

    def tearDown(self) -> None:
        self.__hs.stop()
        shutil.rmtree(self.__temp_dir)

    def test_simple(self):
        """Simple fetch."""
        assert not os.path.isfile(self.__dest_file), f"File '{self.__dest_file}' shouldn't exist before downloading."
        fetch_big_file(url=self.__url, dest_file=self.__dest_file)
        assert os.path.isfile(self.__dest_file), f"File '{self.__dest_file}' should exist after downloading."
        assert os.stat(self.__dest_file).st_size == len(
            self.__mock_data
        ), f"File '{self.__dest_file}' should be of {len(self.__mock_data)} bytes."

        with open(self.__dest_file, mode='rb') as f:
            downloaded_data = f.read()
            assert self.__mock_data == downloaded_data, f"File's '{self.__dest_file}' data should be same as mock data."

    def test_max_size(self):
        """Fetch with max. size."""

        max_size = len(self.__mock_data) - 1000
        # Function should refuse to fetch more than {max_size} bytes
        with pytest.raises(McPermanentError):
            fetch_big_file(url=self.__url, dest_file=self.__dest_file, max_size=max_size)
        assert not os.path.isfile(self.__dest_file), f"File '{self.__dest_file}' should exist after a failed download."
