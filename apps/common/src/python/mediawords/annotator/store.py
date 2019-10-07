from typing import Union

from mediawords.db import DatabaseHandler
from mediawords.key_value_store import KeyValueStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.util.parse_json import decode_json, encode_json
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error

log = create_logger(__name__)


class McJSONAnnotationStoreException(Exception):
    """JSON annotation store exception."""
    pass


class JSONAnnotationStore(object):
    """JSON annotation store."""

    # Store / fetch JSON annotations using Bzip2 compression
    __USE_BZIP = True

    __slots__ = [
        '__postgresql_store',
    ]

    def __init__(self, raw_annotations_table: str):
        """Constructor."""

        if raw_annotations_table is None or len(raw_annotations_table) == 0:
            fatal_error("Annotator's key-value store table name is not set.")

        compression_method = KeyValueStore.Compression.GZIP
        if self.__USE_BZIP:
            compression_method = KeyValueStore.Compression.BZIP2

        self.__postgresql_store = PostgreSQLStore(table=raw_annotations_table, compression_method=compression_method)

        log.debug("Will read / write annotator results to PostgreSQL table: %s" % raw_annotations_table)

    def story_is_annotated(self, db: DatabaseHandler, stories_id: int) -> bool:
        """Check if story is annotated."""

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        stories_id = int(stories_id)

        if self.__postgresql_store.content_exists(db=db, object_id=stories_id):
            return True
        else:
            return False

    def store_annotation_for_story(self,
                                   db: DatabaseHandler,
                                   stories_id: int,
                                   annotation: Union[dict, list, None]) -> None:
        """Store annotation for a story."""

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        stories_id = int(stories_id)

        annotation = decode_object_from_bytes_if_needed(annotation)

        json_annotation = None
        try:
            json_annotation = encode_json(annotation)
            if json_annotation is None:
                raise McJSONAnnotationStoreException("JSON annotation is None for annotation %s." % str(annotation))
        except Exception as ex:
            fatal_error("Unable to encode annotation to JSON: %s\nAnnotation: %s" % (str(ex), str(annotation)))

        log.debug("JSON length: %d" % len(json_annotation))

        log.info("Storing annotation results for story %d..." % stories_id)
        try:
            self.__postgresql_store.store_content(db=db, object_id=stories_id, content=json_annotation.encode('utf-8'))
        except Exception as ex:
            fatal_error("Unable to store annotation result: %s\nJSON annotation: %s" % (str(ex), json_annotation))
        log.info("Done storing annotation results for story %d." % stories_id)

    def fetch_annotation_for_story(self, db: DatabaseHandler, stories_id: int) -> Union[dict, list, None]:
        """Fetch the annotation from key-value store for the story, or None if story is not annotated."""

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        stories_id = int(stories_id)

        if not self.story_is_annotated(db=db, stories_id=stories_id):
            log.warning("Story %d is not annotated." % stories_id)
            return None

        json = self.__postgresql_store.fetch_content(db=db, object_id=stories_id)
        if json is None:
            raise McJSONAnnotationStoreException("Fetched annotation is undefined or empty for story %d." % stories_id)

        json = json.decode('utf-8')

        try:
            annotation = decode_json(json)
            if annotation is None:
                raise McJSONAnnotationStoreException("Annotation is None after decoding from JSON.")
        except Exception as ex:
            raise McJSONAnnotationStoreException(
                "Unable to parse annotation JSON for story %d: %s\nString JSON: %s" % (stories_id, str(ex), json,)
            )

        return annotation
