from typing import Union

from mediawords.db import DatabaseHandler
from mediawords.key_value_store import KeyValueStore, McKeyValueStoreException
from mediawords.key_value_store.amazon_s3 import AmazonS3Store
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McCachedAmazonS3StoreException(McKeyValueStoreException):
    """Cached Amazon S3 key-value store exception."""
    pass


# FIXME merge with MultipleStoresStore because both do essentially the same thing (except that the "cached" store
# doesn't raise if it's unable to store the object in one of the stores)
class CachedAmazonS3Store(AmazonS3Store):
    """Cached Amazon S3 key-value store."""

    # Default cache compression method
    _DEFAULT_CACHE_COMPRESSION_METHOD = KeyValueStore.Compression.GZIP

    __slots__ = [
        '__cache_table',
        '__cache_compression_method',
    ]

    def __init__(self,
                 access_key_id: str,
                 secret_access_key: str,
                 bucket_name: str,
                 directory_name: str,
                 cache_table: str,
                 compression_method: KeyValueStore.Compression = AmazonS3Store._DEFAULT_COMPRESSION_METHOD,
                 cache_compression_method: KeyValueStore.Compression = _DEFAULT_CACHE_COMPRESSION_METHOD):
        """Constructor."""
        super().__init__(access_key_id=access_key_id,
                         secret_access_key=secret_access_key,
                         bucket_name=bucket_name,
                         directory_name=directory_name,
                         compression_method=compression_method)

        cache_table = decode_object_from_bytes_if_needed(cache_table)
        if cache_table is None or len(cache_table) == 0:
            raise McCachedAmazonS3StoreException("Cache table is unset.")

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Perl
        if cache_compression_method is None or len(str(cache_compression_method)) == 0:
            cache_compression_method = self._DEFAULT_CACHE_COMPRESSION_METHOD

        if not self._compression_method_is_valid(cache_compression_method):
            raise McCachedAmazonS3StoreException("Unsupported cache compression method: %s" % cache_compression_method)

        self.__cache_table = cache_table
        self.__cache_compression_method = cache_compression_method

    def __try_storing_object_in_cache(self, db: DatabaseHandler, object_id: int, content: bytes) -> None:
        """Attempt to store object to cache, don't worry too much if it fails."""

        object_id = self._prepare_object_id(object_id)

        if content is None:
            raise McCachedAmazonS3StoreException("Content to store is None for object ID %d." % object_id)

        if isinstance(content, str):
            content = content.encode('utf-8')

        try:
            content = self._compress_data_for_method(data=content, compression_method=self.__cache_compression_method)

            sql = "INSERT INTO %s " % self.__cache_table  # interpolated by Python
            sql += "(object_id, raw_data) "
            sql += "VALUES (%(object_id)s, %(raw_data)s) "  # interpolated by psycopg2
            sql += "ON CONFLICT (object_id) DO UPDATE "
            sql += "    SET raw_data = EXCLUDED.raw_data"

            db.query(sql, {'object_id': object_id, 'raw_data': content})

        except Exception as ex:
            log.warning("Unable to cache object ID %d: %s" % (object_id, str(ex),))

    def __try_retrieving_object_from_cache(self, db: DatabaseHandler, object_id: int) -> Union[bytes, None]:
        """Attempt to retrieve object from cache, don't worry too much if it fails."""

        object_id = self._prepare_object_id(object_id)

        try:
            sql = "SELECT raw_data "
            sql += "FROM %s " % self.__cache_table  # interpolated by Python
            sql += "WHERE object_id = %(object_id)s"  # interpolated by psycopg2

            content = db.query(sql, {'object_id': object_id}).hash()

            if content is None or len(content) == 0:
                raise McCachedAmazonS3StoreException("Object with ID %d was not found." % object_id)

            content = content['raw_data']

            # MC_REWRITE_TO_PYTHON: Perl database handler returns value as array of bytes
            if isinstance(content, list):
                content = b''.join(content)

            if isinstance(content, memoryview):
                content = content.tobytes()

            if not isinstance(content, bytes):
                raise McCachedAmazonS3StoreException("Content is not bytes for object %d." % object_id)

            try:
                content = self._uncompress_data_for_method(data=content,
                                                           compression_method=self.__cache_compression_method)
            except Exception as ex:
                raise McCachedAmazonS3StoreException(
                    "Unable to uncompress data for object ID %d: %s" % (object_id, str(ex),))

            if content is None:
                raise McCachedAmazonS3StoreException("Content is None after uncompression for object ID %d" % object_id)
            if not isinstance(content, bytes):
                raise McCachedAmazonS3StoreException(
                    "Content is not bytes after uncompression for object ID %d" % object_id)

        except Exception as ex:
            log.debug("Unable to retrieve object ID %d from cache: %s" % (object_id, str(ex),))
            return None

        else:
            return content

    def __remove_object_from_cache(self, db: DatabaseHandler, object_id: int) -> None:
        """Attempt to remove object from cache.

        Raise if removal fails because after removal we'd expect the object to be gone for good."""

        object_id = self._prepare_object_id(object_id)

        # noinspection SqlWithoutWhere
        sql = "DELETE FROM %s " % self.__cache_table  # interpolated by Python
        sql += "WHERE object_id = %(object_id)s"  # interpolated by psycopg2

        db.query(sql, {'object_id': object_id})

    def fetch_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bytes:
        """Read object from Amazon S3, try local cache first."""

        object_id = self._prepare_object_id(object_id)

        content = self.__try_retrieving_object_from_cache(db=db, object_id=object_id)

        if content is None:
            content = super().fetch_content(db=db, object_id=object_id, object_path=object_path)

            # Cache the retrieved object because we might need it soon
            self.__try_storing_object_in_cache(db=db, object_id=object_id, content=content)

        return content

    def store_content(self,
                      db: DatabaseHandler,
                      object_id: int,
                      content: Union[str, bytes],
                      content_type: str = 'binary/octet-stream') -> str:
        """Write object to Amazon S3, cache it locally too."""

        object_id = self._prepare_object_id(object_id)
        content = self._prepare_content(content)

        path = super().store_content(db=db, object_id=object_id, content=content)

        # If we got to this point, object got stored in S3 successfully

        self.__try_storing_object_in_cache(db=db, object_id=object_id, content=content)

        return path

    def remove_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> None:
        """Remove object from Amazon S3 and local cache."""

        object_id = self._prepare_object_id(object_id)

        self.__remove_object_from_cache(db=db, object_id=object_id)

        super().remove_content(db=db, object_id=object_id)

    def content_exists(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bool:
        """Test if object exists in Amazon S3, try local cache first."""

        object_id = self._prepare_object_id(object_id)

        content = self.__try_retrieving_object_from_cache(db=db, object_id=object_id)
        if content is None:
            return super().content_exists(db=db, object_id=object_id)

        else:
            # Key is cached, that means it exists on S3 too
            return True
