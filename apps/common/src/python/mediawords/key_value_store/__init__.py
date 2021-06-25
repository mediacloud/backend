import abc
from enum import Enum
from typing import Union

from mediawords.db import DatabaseHandler
from mediawords.util.compress import gzip, gunzip, bzip2, bunzip2
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McKeyValueStoreException(Exception):
    """Key-value store exception."""
    pass


class McKeyValueStoreCompressionException(McKeyValueStoreException):
    """Exception that was raised while compressing / decompressing data."""
    pass


class KeyValueStore(metaclass=abc.ABCMeta):
    """Abstract class for storing / loading objects (raw downloads, annotator results, ...) to / from various storage
    locations.

    You can use AbstractKeyValueStore concrete subclasses (AmazonS3Store, PostgreSQLStore, ...) to store all kinds of
    key-value data."""

    @abc.abstractmethod
    def fetch_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bytes:
        """Read object. Returns content (in bytes) on success, None if content is not found, raises on error."""
        raise NotImplementedError("Abstract method.")

    @abc.abstractmethod
    def store_content(self,
                      db: DatabaseHandler,
                      object_id: int,
                      content: Union[str, bytes],
                      content_type: str = 'binary/octet-stream') -> str:
        """Write object (str or bytes). Returns path to the object on success, raises on error."""
        raise NotImplementedError("Abstract method.")

    @abc.abstractmethod
    def remove_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> None:
        """Delete object. Raises on error."""
        raise NotImplementedError("Abstract method.")

    @abc.abstractmethod
    def content_exists(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bool:
        """Test if object exists. Returns true if it does, raises on error."""
        raise NotImplementedError("Abstract method.")

    class Compression(Enum):
        """Available compression methods."""
        NONE = 'mc-kvs-compression-none'
        GZIP = 'mc-kvs-compression-gzip'
        BZIP2 = 'mc-kvs-compression-bzip2'

    @staticmethod
    def _compression_method_is_valid(compression_method: Compression) -> bool:
        """Helper for validating compression method."""

        for method in KeyValueStore.Compression:
            if str(compression_method) == str(method):
                return True

        return False

    @staticmethod
    def _compress_data_for_method(data: Union[bytes, str], compression_method: Compression) -> bytes:
        """Compress data."""

        if data is None:
            raise McKeyValueStoreCompressionException("Data is None.")

        if isinstance(data, str):
            data = data.encode('utf-8')

        if not isinstance(data, bytes):
            raise McKeyValueStoreCompressionException("Data is not str or bytes: %s" % str(data))

        if compression_method == KeyValueStore.Compression.NONE:
            pass
        elif compression_method == KeyValueStore.Compression.GZIP:
            data = gzip(data)
        elif compression_method == KeyValueStore.Compression.BZIP2:
            data = bzip2(data)
        else:
            raise McKeyValueStoreCompressionException("Invalid compression method: %s" % compression_method)

        return data

    @staticmethod
    def _uncompress_data_for_method(data: bytes, compression_method: Compression) -> bytes:
        """Uncompress data."""

        if data is None:
            raise McKeyValueStoreCompressionException("Data is None.")

        if not isinstance(data, bytes):
            raise McKeyValueStoreCompressionException("Compressed data is not str or bytes: %s" % str(data))

        if compression_method == KeyValueStore.Compression.NONE:
            pass

        elif compression_method == KeyValueStore.Compression.GZIP:
            data = gunzip(data)
        elif compression_method == KeyValueStore.Compression.BZIP2:
            data = bunzip2(data)
        else:
            raise McKeyValueStoreCompressionException("Invalid compression method: %s" % compression_method)

        return data

    @staticmethod
    def _prepare_object_id(object_id: int) -> int:
        """Prepare object ID by validating and decoding it."""

        if object_id is None:
            raise McKeyValueStoreException("Object ID is None.")

        if isinstance(object_id, bytes):
            object_id = decode_object_from_bytes_if_needed(object_id)

        object_id = int(object_id)

        if object_id < 1:
            raise McKeyValueStoreException("Invalid object ID: %d" % object_id)

        return object_id

    @staticmethod
    def _prepare_content(content: Union[str, bytes]) -> bytes:
        """Prepare content to store by validating and decoding it."""

        if content is None:
            raise McKeyValueStoreException("Content to store is None.")

        if isinstance(content, str):
            content = content.encode('utf-8')

        if not isinstance(content, bytes):
            raise McKeyValueStoreException("Content is not bytes: %s" % str(content))

        return content
