from typing import List, Union

from mediawords.db import DatabaseHandler
from mediawords.key_value_store import KeyValueStore, McKeyValueStoreException
from mediawords.util.perl import decode_object_from_bytes_if_needed


class McMultipleStoresStoreException(McKeyValueStoreException):
    """Multiple stores exception."""
    pass


class MultipleStoresStore(KeyValueStore):
    """Key-value store that reads from / writes to multiple stores."""

    __slots__ = [
        '__stores_for_reading',
        '__stores_for_writing',
    ]

    def __init__(self,
                 stores_for_reading: List[KeyValueStore] = None,
                 stores_for_writing: List[KeyValueStore] = None):
        """Constructor."""

        if stores_for_reading is None:
            stores_for_reading = []
        if stores_for_writing is None:
            stores_for_writing = []

        if len(stores_for_reading) + len(stores_for_writing) == 0:
            raise McMultipleStoresStoreException("At least one store for reading / writing should be present.")

        self.__stores_for_reading = stores_for_reading
        self.__stores_for_writing = stores_for_writing

    def stores_for_reading(self) -> list:
        """Return list of stores for reading."""
        return self.__stores_for_reading

    def stores_for_writing(self) -> list:
        """Return list of stores for writing."""
        return self.__stores_for_writing

    def fetch_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bytes:
        """Fetch content from any of the stores that might have it; raise if none of them do."""

        object_id = self._prepare_object_id(object_id)

        object_path = decode_object_from_bytes_if_needed(object_path)

        if len(self.__stores_for_reading) == 0:
            raise McMultipleStoresStoreException("List of stores for reading object ID %d is empty." % object_id)

        errors = []

        content = None
        for store in self.__stores_for_reading:

            try:

                # MC_REWRITE_TO_PYTHON: use named parameters after Python rewrite
                content = store.fetch_content(db, object_id, object_path)
                if content is None:
                    raise McMultipleStoresStoreException("Fetching object ID %d from store %s succeeded, "
                                                         "but the returned content is undefined." % (
                                                             object_id, str(store),
                                                         ))

            except Exception as ex:
                # Silently skip through errors and die() only if content wasn't found anywhere
                errors.append("Error fetching object ID %(object_id)d from store %(store)s: %(exception)s" % {
                    'object_id': object_id,
                    'store': store,
                    'exception': str(ex),
                })

            else:
                break

        if content is None:
            raise McMultipleStoresStoreException(
                "All stores failed while fetching object ID %(object_id)d; errors: %(errors)s" % {
                    'object_id': object_id,
                    'errors': "\n".join(errors),
                }
            )

        return content

    def store_content(self, db: DatabaseHandler, object_id: int, content: Union[str, bytes], content_type: str) -> str:
        """Store content to all stores; raise if one of them fails."""

        object_id = self._prepare_object_id(object_id)
        content = self._prepare_content(content)

        if len(self.__stores_for_writing) == 0:
            raise McMultipleStoresStoreException("List of stores for writing object ID %d is empty." % object_id)

        last_store_path = None

        for store in self.__stores_for_writing:

            try:
                # MC_REWRITE_TO_PYTHON: use named parameters after Python rewrite
                last_store_path = store.store_content(db, object_id, content)
                if last_store_path is None:
                    raise McMultipleStoresStoreException(
                        "Storing object ID %d to %s succeeded, but the returned path is empty." % (object_id, store,)
                    )

            except Exception as ex:
                raise McMultipleStoresStoreException(
                    "Error while saving object ID %(object_id)d to store %(store)s: %(exception)s" % {
                        'object_id': object_id,
                        'store': str(store),
                        'exception': str(ex)
                    }
                )

        if last_store_path is None:
            raise McMultipleStoresStoreException(
                "Storing object ID %d to all stores succeeded, but the returned path is empty." % object_id
            )

        return last_store_path

    def remove_content(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> None:
        """Remove content from all stores; raise if one of them fails."""

        object_id = self._prepare_object_id(object_id)
        object_path = decode_object_from_bytes_if_needed(object_path)

        if len(self.__stores_for_writing) == 0:
            raise McMultipleStoresStoreException("List of stores for writing object ID %d is empty." % object_id)

        for store in self.__stores_for_writing:

            try:
                # MC_REWRITE_TO_PYTHON: use named parameters after Python rewrite
                store.remove_content(db, object_id, object_path)

            except Exception as ex:
                raise McMultipleStoresStoreException(
                    "Error while removing object ID %(object_id)d from store %(store)s: %(exception)s" % {
                        'object_id': object_id,
                        'store': str(store),
                        'exception': str(ex)
                    }
                )

    def content_exists(self, db: DatabaseHandler, object_id: int, object_path: str = None) -> bool:
        """Test if content in at least one of the stores."""

        object_id = self._prepare_object_id(object_id)

        object_path = decode_object_from_bytes_if_needed(object_path)

        if len(self.__stores_for_reading) == 0:
            raise McMultipleStoresStoreException("List of stores for reading object ID %d is empty." % object_id)

        for store in self.__stores_for_reading:

            try:
                # MC_REWRITE_TO_PYTHON: use named parameters after Python rewrite
                exists = store.content_exists(db, object_id, object_path)

            except Exception as ex:
                raise McMultipleStoresStoreException(
                    "Error while testing whether object ID %(object_id)d exists in store %(store)s: %(exception)s" % {
                        'object_id': object_id,
                        'store': store,
                        'exception': str(ex),
                    })

            else:
                if exists:
                    return True

        return False
