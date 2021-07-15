import bz2
import gzip as gzip_lib
import os
from typing import Union

from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McCompressException(Exception):
    """Exception raised when compressing or decompressing data."""
    pass


class McBzip2Exception(McCompressException):
    """bzip2() exception."""
    pass


class McBunzip2Exception(McCompressException):
    """bunzip2() exception."""
    pass


class McGzipException(McCompressException):
    """gzip() exception."""
    pass


class McGunzipException(McCompressException):
    """gunzip() exception."""
    pass


def bzip2(data: Union[str, memoryview, bytes]) -> bytes:
    """Bzip2 data."""

    if data is None:
        raise McBzip2Exception("Data is None.")

    if isinstance(data, str):
        data = data.encode('utf-8')

    # BYTEA coming from psycopg2 is memoryview and we need bytes
    if isinstance(data, memoryview):
        data = data.tobytes()

    if not isinstance(data, bytes):
        raise McBzip2Exception("Data is not str or bytes: %s" % str(data))

    try:
        bzipped2_data = bz2.compress(data, compresslevel=9)
    except Exception as ex:
        raise McBzip2Exception("Unable to bzip2 data: %s" % str(ex))

    if bzipped2_data is None:
        raise McBzip2Exception("Bzipped data is None.")

    if not isinstance(bzipped2_data, bytes):
        raise McBzip2Exception("Bzipped data is not bytes.")

    return bzipped2_data


def bunzip2(data: Union[bytes, memoryview]) -> bytes:
    """Bunzip2 data."""

    if data is None:
        raise McBunzip2Exception("Data is None.")

    # BYTEA coming from psycopg2 is memoryview and we need bytes
    if isinstance(data, memoryview):
        data = data.tobytes()

    if not isinstance(data, bytes):
        raise McBunzip2Exception("Data is not bytes: %s" % str(data))

    if len(data) == 0:
        raise McBunzip2Exception("Data is empty (no way an empty string is a valid Bzip2 archive).")

    try:
        bunzipped2_data = bz2.decompress(data)
    except Exception as ex:
        raise McBunzip2Exception("Unable to bunzip2 data: %s" % str(ex))

    if bunzipped2_data is None:
        raise McBunzip2Exception("Bunzipped data is None.")

    if not isinstance(bunzipped2_data, bytes):
        raise McBunzip2Exception("Bunzipped data is not bytes.")

    return bunzipped2_data


def gzip(data: Union[str, memoryview, bytes]) -> bytes:
    """Gzip data."""

    if data is None:
        raise McGzipException("Data is None.")

    if isinstance(data, str):
        data = data.encode('utf-8')

    # BYTEA coming from psycopg2 is memoryview and we need bytes
    if isinstance(data, memoryview):
        data = data.tobytes()

    if not isinstance(data, bytes):
        raise McGzipException("Data is not str or bytes: %s" % str(data))

    try:
        gzipped_data = gzip_lib.compress(data, compresslevel=9)
    except Exception as ex:
        raise McGzipException("Unable to gzip data: %s" % str(ex))

    if gzipped_data is None:
        raise McGzipException("Gzipped data is None.")

    if not isinstance(gzipped_data, bytes):
        raise McGzipException("Gzipped data is not bytes.")

    return gzipped_data


def gunzip(data: Union[memoryview, bytes]) -> bytes:
    """Gunzip data."""

    if data is None:
        raise McGunzipException("Data is None.")

    # BYTEA coming from psycopg2 is memoryview and we need bytes
    if isinstance(data, memoryview):
        data = data.tobytes()

    if not isinstance(data, bytes):
        raise McGunzipException("Data is not bytes: %s" % str(data))

    if len(data) == 0:
        raise McGunzipException("Data is empty (no way an empty string is a valid Gzip archive).")

    try:
        gunzipped_data = gzip_lib.decompress(data)
    except Exception as ex:
        raise McGunzipException("Unable to gunzip data: %s" % str(ex))

    if gunzipped_data is None:
        raise McGunzipException("Gunzipped data is None.")

    if not isinstance(gunzipped_data, bytes):
        raise McGunzipException("Gunzipped data is not bytes.")

    return gunzipped_data
