from typing import Union

from mediawords.db import DatabaseHandler
from mediawords.key_value_store import KeyValueStore, McKeyValueStoreException
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McDatabaseInlineStoreException(McKeyValueStoreException):
    """Database inline key-value store exception."""
    pass


class DatabaseInlineStore(KeyValueStore):
    """PostgreSQL key-value store which uses downloads.path column."""

    __CONTENT_PREFIX = 'content:'

    def fetch_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bytes:
        """Read object from PostgreSQL's 'path' row."""

        object_id = self._prepare_object_id(object_id)

        object_path = decode_object_from_bytes_if_needed(object_path)

        if object_path is None:
            raise McDatabaseInlineStoreException("Object path for object ID %d is None." % object_id)

        if not object_path.startswith(self.__CONTENT_PREFIX):
            raise McDatabaseInlineStoreException(
                "Object path for object ID %d is invalid: %s" % (object_id, object_path,)
            )

        object_path = object_path[len(self.__CONTENT_PREFIX):]

        content = object_path.encode('utf-8')

        return content

    def store_content(self, db: DatabaseHandler, object_id: int, content: Union[str, bytes]) -> None:
        """Write object to PostgreSQL's 'path' row."""

        object_id = self._prepare_object_id(object_id)

        raise McDatabaseInlineStoreException("Do not write inline downloads for object ID %d." % object_id)

    def remove_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> None:
        """Remove object from PostgreSQL's 'path' row."""

        object_id = self._prepare_object_id(object_id)

        raise McDatabaseInlineStoreException("Not sure how to remove inline content for object ID %d." % object_id)

    def content_exists(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bool:

        object_id = self._prepare_object_id(object_id)

        object_path = decode_object_from_bytes_if_needed(object_path)

        if object_path is None:
            raise McDatabaseInlineStoreException("Object path for object ID %d is None." % object_id)

        if object_path.startswith(self.__CONTENT_PREFIX):
            return True
        else:
            return False
