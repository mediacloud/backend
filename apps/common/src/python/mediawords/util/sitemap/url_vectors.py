import re
import string
from pathlib import PurePosixPath
from typing import List, Union
from urllib.parse import urlparse, unquote, parse_qs


class URLFeatureExtractor(object):
    __SPLIT_PATH_PART_REGEX = re.compile(r'[-_.]')

    __slots__ = [
        '__url',
        '__host',
        '__path',
        '__path_ends_with_slash',
        '__query',

        '__vectors',
    ]

    def __init__(self, url: str):
        assert url, "URL is unset."
        self.__url = url

        uri = urlparse(url)
        assert uri.scheme in {'http', 'https'}, f"URL is not HTTP(s): {url}"

        netloc = uri.netloc.lower()
        www_prefix = 'www.'
        while netloc.startswith(www_prefix):
            netloc = netloc[len(www_prefix):]
        self.__host = netloc

        path = unquote(uri.path)

        self.__path_ends_with_slash = path.endswith('/') or not path

        path = PurePosixPath(path)
        path = list(path.parts[1:])  # Skip the "/", convert to list

        split_path = []

        for part in path:
            part = re.split(self.__SPLIT_PATH_PART_REGEX, part)

            part_with_ints = []
            for chunk in part:
                if chunk:
                    part_with_ints.append(chunk)

            split_path.append(part_with_ints)

        self.__path = split_path

        self.__query = parse_qs(uri.query, keep_blank_values=True)

        self.__vectors = [
            self._path_ends_with_html_extension(),
            self._path_ends_with_number(),
            self._path_ends_with_slash(),
            self._path_parts_count(),
            self._path_has_chunk_that_looks_like_year(),
            self._path_has_chunk_that_looks_like_month(),
            self._path_has_chunk_that_looks_like_day(),
            self._path_length()
        ]

    def url(self) -> str:
        return self.__url

    def _path_ends_with_html_extension(self) -> bool:
        """
        Whether or not path ends with ".htm(l)" extension.
        :return:
        """
        if len(self.__path):
            path_part = self.__path[-1]
            path_chunk = path_part[-1]
            return path_chunk.lower() in {"html", "htm"}
        else:
            return False

    def _path_ends_with_slash(self) -> bool:
        """
        Whether or not URL path ends with a slash.
        :return:
        """
        return self.__path_ends_with_slash

    def __getitem__(self, item):
        return self.__vectors.__getitem__(item)

    def __len__(self):
        return self.__vectors.__len__()

    def __repr__(self):
        return self.__url
