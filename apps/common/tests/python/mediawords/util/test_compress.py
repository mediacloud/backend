import pytest

from mediawords.util.compress import (
    gzip,
    gunzip,
    bzip2,
    bunzip2,
    McBunzip2Exception,
    McGunzipException,
    McGzipException,
    McBzip2Exception,
)


# Strings to try to compress / decompress
__COMPRESS_TEST_DATA = [
    # ASCII
    b"Media Cloud\r\nMedia Cloud\nMedia Cloud\r\n",

    # UTF-8
    "Media Cloud\r\nąčęėįšųūž\n您好\r\n".encode('utf-8'),

    # Empty string
    b"",

    # Invalid UTF-8 sequences
    b"\xc3\x28",
    b"\xa0\xa1",
    b"\xe2\x28\xa1",
    b"\xe2\x82\x28",
    b"\xf0\x28\x8c\xbc",
    b"\xf0\x90\x28\xbc",
    b"\xf0\x28\x8c\x28",
    b"\xf8\xa1\xa1\xa1\xa1",
    b"\xfc\xa1\xa1\xa1\xa1\xa1",

    # memoryview simulating BYTEA columns coming from psycopg2
    memoryview(b"This is a test"),
]


def test_gzip():
    def __inner_test_gzip(data_: bytes) -> None:
        gzipped_data = gzip(data_)
        assert len(gzipped_data) > 0
        assert isinstance(gzipped_data, bytes)
        assert gzipped_data != data_

        gunzipped_data = gunzip(gzipped_data)
        assert gunzipped_data == data_

    for data in __COMPRESS_TEST_DATA:
        __inner_test_gzip(data_=data)


def test_gzip_bad_input():
    with pytest.raises(McGzipException):
        # noinspection PyTypeChecker
        gzip(None)

    with pytest.raises(McGunzipException):
        # noinspection PyTypeChecker
        gunzip(None)

    with pytest.raises(McGunzipException):
        gunzip(b'')

    with pytest.raises(McGunzipException):
        gunzip(b'No way this is valid Gzip data')


def test_bzip2():
    def __inner_test_bzip2(data_: bytes) -> None:
        bzipped_data = bzip2(data_)
        assert len(bzipped_data) > 0
        assert isinstance(bzipped_data, bytes)
        assert bzipped_data != data_

        bunzipped_data = bunzip2(bzipped_data)
        assert bunzipped_data == data_

    for data in __COMPRESS_TEST_DATA:
        __inner_test_bzip2(data_=data)


def test_bzip2_bad_input():
    with pytest.raises(McBzip2Exception):
        # noinspection PyTypeChecker
        bzip2(None)

    with pytest.raises(McBunzip2Exception):
        # noinspection PyTypeChecker
        bunzip2(None)

    with pytest.raises(McBunzip2Exception):
        bunzip2(b'')

    with pytest.raises(McBunzip2Exception):
        bunzip2(b'No way this is valid Bzip2 data')


def test_wrong_algorithm():
    def __inner_test_wrong_algorithm(data_: bytes) -> None:
        with pytest.raises(McBunzip2Exception):
            bunzip2(gzip(data_))
        with pytest.raises(McGunzipException):
            gunzip(bzip2(data_))

    for data in __COMPRESS_TEST_DATA:
        __inner_test_wrong_algorithm(data_=data)
