from typing import Union

from mediawords.db import DatabaseHandler
from mediawords.key_value_store import KeyValueStore, McKeyValueStoreException
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McPostgreSQLStoreException(McKeyValueStoreException):
    """PostgreSQL key-value store exception."""
    pass


class PostgreSQLStore(KeyValueStore):
    """PostgreSQL BYTEA key-value store"""

    # Default object compression method
    _DEFAULT_COMPRESSION_METHOD = KeyValueStore.Compression.GZIP

    __slots__ = [
        '__table',
        '__compression_method',
    ]

    def __init__(self, table: str, compression_method: KeyValueStore.Compression = _DEFAULT_COMPRESSION_METHOD):
        """Constructor."""

        table = decode_object_from_bytes_if_needed(table)

        if table is None or len(table) == 0:
            raise McPostgreSQLStoreException("Database table to store objects in is unset.")

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Perl
        if compression_method is None or len(str(compression_method)) == 0:
            compression_method = self._DEFAULT_COMPRESSION_METHOD

        if not self._compression_method_is_valid(compression_method):
            raise McPostgreSQLStoreException("Unsupported compression method: %s" % compression_method)

        self.__table = table
        self.__compression_method = compression_method

    def fetch_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bytes:
        """Read object from PostgreSQL table."""

        object_id = self._prepare_object_id(object_id)

        sql = "SELECT raw_data "
        sql += "FROM %s " % self.__table  # interpolated by Python
        sql += "WHERE object_id = %(object_id)s"  # interpolated by psycopg2

        content = db.query(sql, {'object_id': object_id}).hash()

        if content is None or len(content) == 0:
            # Clients are expected to do content_exists() before attempting to fetch content that might not exist
            raise McPostgreSQLStoreException("Object with ID %d was not found." % object_id)

        content = content['raw_data']

        # MC_REWRITE_TO_PYTHON: Perl database handler returns value as array of bytes
        if isinstance(content, list):
            content = b''.join(content)

        if isinstance(content, memoryview):
            content = content.tobytes()

        if not isinstance(content, bytes):
            raise McPostgreSQLStoreException("Content is not bytes for object %d." % object_id)

        try:
            content = self._uncompress_data_for_method(data=content, compression_method=self.__compression_method)
        except Exception as ex:
            raise McPostgreSQLStoreException("Unable to uncompress data for object ID %d: %s" % (object_id, str(ex),))

        if content is None:
            raise McPostgreSQLStoreException("Content is None after uncompression for object ID %d." % object_id)
        if not isinstance(content, bytes):
            raise McPostgreSQLStoreException("Content is not bytes after uncompression for object ID %d." % object_id)

        return content

    def store_content(self, db: DatabaseHandler, object_id: int, content: Union[str, bytes]) -> str:
        """Write object to PostgreSQL table."""

        object_id = self._prepare_object_id(object_id)
        content = self._prepare_content(content)

        try:
            content = self._compress_data_for_method(data=content, compression_method=self.__compression_method)
        except Exception as ex:
            raise McPostgreSQLStoreException("Unable to compress data for object ID %d: %s" % (object_id, str(ex),))

        if content is None:
            raise McPostgreSQLStoreException("Content is None after compression for object ID %d" % object_id)
        if not isinstance(content, bytes):
            raise McPostgreSQLStoreException("Content is not bytes after compression for object ID %d" % object_id)

        sql = "INSERT INTO %s " % self.__table  # interpolated by Python
        sql += "(object_id, raw_data) "
        sql += "VALUES (%(object_id)s, %(raw_data)s) "  # interpolated by psycopg2
        sql += "ON CONFLICT (object_id) DO UPDATE "
        sql += "    SET raw_data = EXCLUDED.raw_data"

        db.query(sql, {'object_id': object_id, 'raw_data': content})

        path = 'postgresql:%s' % self.__table

        return path

    def remove_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> None:
        """Remove object from PostgreSQL table."""

        object_id = self._prepare_object_id(object_id)

        # noinspection SqlWithoutWhere
        sql = "DELETE FROM %s " % self.__table  # interpolated by Python
        sql += "WHERE object_id = %(object_id)s"  # interpolated by psycopg2

        db.query(sql, {'object_id': object_id})

    def content_exists(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bool:
        """Test if object exists in PostgreSQL table."""

        object_id = self._prepare_object_id(object_id)

        sql = "SELECT 1"
        sql += "FROM %s " % self.__table  # interpolated by Python
        sql += "WHERE object_id = %(object_id)s"  # interpolated by psycopg2

        object_exists = db.query(sql, {'object_id': object_id}).hash()

        if object_exists is not None and len(object_exists) > 0:
            return True
        else:
            return False
