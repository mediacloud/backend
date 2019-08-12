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
            self._query_string_keys_count(),
            self._query_string_keys_include_a_number(),
            self._query_string_values_include_a_number(),
            self._path_ends_with_html_extension(),
            self._path_ends_with_number(),
            self._path_ends_with_slash(),
            self._path_parts_count(),
            self._path_has_chunk_that_looks_like_year(),
            self._path_has_chunk_that_looks_like_month(),
            self._path_has_chunk_that_looks_like_day(),
            self._path_length(),
            self._longest_path_part_length(),
            self._longest_path_part_from_start_index(),
            self._longest_path_part_from_end_index(),
            self._consecutive_number_only_path_part_count(),
            self._number_only_path_part_chunk_count(),
            self._first_path_part_with_number_chunk_from_start_index(),
            self._last_path_part_with_number_chunk_from_end_index(),
        ]

    @staticmethod
    def __is_dec_hex_number(number: str) -> bool:
        """
        Whether or not argument is a decimal or hexadecimal number.
        :param number: Number.
        :return: True if argument is decimal or hexadecimal number.
        """
        if not number:
            return False
        number = number.lower()
        return all(c in string.hexdigits for c in number)

    def url(self) -> str:
        return self.__url

    def _query_string_keys_count(self) -> int:
        """
        Number of unique keys in a query string, e.g. "?a=b&c=d" includes two keys.
        :return:
        """
        return len(self.__query.keys())

    def _query_string_keys_include_a_number(self) -> bool:
        """
        Whether or not one of the query string keys include a number.
        :return:
        """
        for key in self.__query.keys():
            if self.__is_dec_hex_number(key):
                return True
        return False

    def _query_string_values_include_a_number(self) -> bool:
        """
        Whether or not one of the query string values include a number.
        :return:
        """
        for key, values in self.__query.items():
            for value in values:
                if self.__is_dec_hex_number(value):
                    return True
        return False

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

    def _path_ends_with_number(self) -> bool:
        """
        Whether or not path ends with decimal or hexadecimal number (remove the extension first).
        :return:
        """
        if not len(self.__path):
            return False

        last_path_chunk_index = -1
        if self._path_ends_with_html_extension():
            last_path_chunk_index = -2

        if len(self.__path[-1]) < last_path_chunk_index * -1:
            return False

        return self.__is_dec_hex_number(self.__path[-1][last_path_chunk_index])

    def _path_ends_with_slash(self) -> bool:
        """
        Whether or not URL path ends with a slash.
        :return:
        """
        return self.__path_ends_with_slash

    def _path_parts_count(self) -> int:
        """
        Number of parts in a path.
        :return:
        """
        return len(self.__path)

    def _path_has_chunk_that_looks_like_year(self) -> bool:
        """
        Return True if path has a chunk that looks like a year.
        :return:
        """
        for path_part in self.__path:
            for path_part_chunk in path_part:
                if path_part_chunk.isdigit():
                    if 1900 <= int(path_part_chunk) <= 2100:
                        return True

        return False

    def _path_has_chunk_that_looks_like_month(self) -> bool:
        """
        Return True if path has a chunk that looks like a month.
        :return:
        """
        for path_part in self.__path:
            for path_part_chunk in path_part:
                if path_part_chunk.isdigit():
                    if 1 <= int(path_part_chunk) <= 12:
                        return True

        return False

    def _path_has_chunk_that_looks_like_day(self) -> bool:
        """
        Return True if path has a chunk that looks like a day.
        :return:
        """
        for path_part in self.__path:
            for path_part_chunk in path_part:
                if path_part_chunk.isdigit():
                    if 1 <= int(path_part_chunk) <= 31:
                        return True

        return False

    def _path_length(self) -> int:
        """
        Return path length.
        :return:
        """
        path_length = 0
        for path_part in self.__path:
            path_part_length = len('-'.join(path_part))
            path_length += path_part_length
        path_length += len(self.__path) - 1
        return path_length

    def _longest_path_part_length(self) -> int:
        """
        Return length of longest path part.
        :return:
        """
        longest_part_length = 0
        for path_part in self.__path:
            path_part_length = len('-'.join(path_part))
            if path_part_length > longest_part_length:
                longest_part_length = path_part_length
        return longest_part_length

    def _longest_path_part_from_start_index(self) -> int:
        """
        Return index of longest path part, counting from the start.
        :return:
        """
        longest_part_length = 0
        longest_part_index = 0
        index = 0
        for path_part in self.__path:
            path_part_length = len('-'.join(path_part))
            if path_part_length > longest_part_length:
                longest_part_length = path_part_length
                longest_part_index = index
            index += 1
        return longest_part_index

    def _longest_path_part_from_end_index(self) -> int:
        """
        Return index of longest path part, counting from the end.
        :return:
        """
        if len(self.__path):
            return len(self.__path) - self._longest_path_part_from_start_index() - 1
        else:
            return 0

    def _consecutive_number_only_path_part_count(self) -> int:
        """
        Return count of consecutive number-only path parts.
        :return:
        """
        max_consecutive_path_parts = 0
        consecutive_path_parts = 0

        for path_part in self.__path:

            path_part_is_numbers_only = True
            for path_part_chunk in path_part:
                if not self.__is_dec_hex_number(path_part_chunk):
                    path_part_is_numbers_only = False
                    break

            if path_part_is_numbers_only:
                consecutive_path_parts += 1
            else:
                consecutive_path_parts = 0

            if max_consecutive_path_parts < consecutive_path_parts:
                max_consecutive_path_parts = consecutive_path_parts

        return max_consecutive_path_parts

    def _number_only_path_part_chunk_count(self) -> int:
        """
        Return count of number-only path part chunks.
        :return:
        """
        number_only_chunks = 0

        for path_part in self.__path:
            for path_part_chunk in path_part:
                if self.__is_dec_hex_number(path_part_chunk):
                    number_only_chunks += 1

        return number_only_chunks

    @classmethod
    def __index_of_number_path_part(cls, path) -> int:
        path_part_index = 0
        for path_part in path:

            for path_part_chunk in path_part:
                if cls.__is_dec_hex_number(path_part_chunk):
                    return path_part_index

            path_part_index += 1

        return -1

    def _first_path_part_with_number_chunk_from_start_index(self) -> int:
        """
        Return index of the first path part that contains a number-only chunk, counting from the start of the path.
        :return: Path part index, or -1 if there aren't any number-only path chunk parts.
        """
        return self.__index_of_number_path_part(self.__path)

    def _last_path_part_with_number_chunk_from_end_index(self) -> int:
        """
        Return index of the last path part that contains a number-only chunk, counting from the end of the path.
        :return: Path part index, or -1 if there aren't any number only parts.
        """
        return self.__index_of_number_path_part(reversed(self.__path))

    def vectors(self) -> List[Union[int, float, bool]]:
        """
        Return vectors that describe the structure of an URL.
        :return:
        """
        return self.__vectors

    def __getitem__(self, item):
        return self.__vectors.__getitem__(item)

    def __len__(self):
        return self.__vectors.__len__()

    def __repr__(self):
        return self.__url
