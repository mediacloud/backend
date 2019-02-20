import abc
from http import HTTPStatus
from typing import Union, List

import re

from mediawords.db import DatabaseHandler
from mediawords.dbi.stories.postprocess import story_is_english_and_has_sentences
from mediawords.key_value_store import KeyValueStore
from mediawords.key_value_store.postgresql import PostgreSQLStore
from mediawords.util.parse_json import decode_json, encode_json
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error
from mediawords.util.web.user_agent import Request, UserAgent

log = create_logger(__name__)


class McJSONAnnotatorException(Exception):
    """JSON annotator exception."""
    pass


class JSONAnnotator(metaclass=abc.ABCMeta):
    """Abstract JSON annotator role."""

    class Tag(object):
        """Single tag derived from JSON annotation."""

        __slots__ = [
            'tag_sets_name',
            'tag_sets_label',
            'tag_sets_description',

            'tags_name',
            'tags_label',
            'tags_description',
        ]

        def __init__(self,
                     tag_sets_name: str,
                     tag_sets_label: str,
                     tag_sets_description: str,
                     tags_name: str,
                     tags_label: str,
                     tags_description: str):
            """Constructor."""
            self.tag_sets_name = tag_sets_name
            self.tag_sets_label = tag_sets_label
            self.tag_sets_description = tag_sets_description
            self.tags_name = tags_name
            self.tags_label = tags_label
            self.tags_description = tags_description

    @abc.abstractmethod
    def _postgresql_raw_annotations_table(self) -> str:
        """Returns PostgreSQL table name for storing raw compressed annotations."""
        raise NotImplementedError

    @abc.abstractmethod
    def _request_for_text(self, text: str) -> Request:
        """Returns Request that should be made to the annotator service to annotate a given text."""
        raise NotImplementedError

    @abc.abstractmethod
    def _fetched_annotation_is_valid(self, annotation: Union[dict, list]) -> bool:
        """Returns true if decoded response JSON is valid."""
        raise NotImplementedError

    @abc.abstractmethod
    def _tags_for_annotation(self, annotation: Union[dict, list]) -> List[Tag]:
        """Returns list of tags for decoded JSON annotation."""
        raise NotImplementedError

    # noinspection PyMethodMayBeStatic
    def _postprocess_fetched_annotation(self, annotation: Union[dict, list]) -> Union[dict, list]:
        """(Might be overridden) Post-process decoded JSON response."""
        return annotation

    # noinspection PyMethodMayBeStatic
    def _preprocess_stored_annotation(self, annotation: Union[dict, list]) -> Union[dict, list]:
        """(Might be overridden) Pre-process decoded JSON response just loaded from the object store."""
        return annotation

    # ---

    # HTTP timeout for annotator
    __HTTP_TIMEOUT = 600

    # Requested text length limit (0 for no limit)
    __TEXT_LENGTH_LIMIT = 50 * 1024

    # Store / fetch JSON annotations using Bzip2 compression
    __USE_BZIP = True

    __slots__ = [
        '__postgresql_store',
    ]

    def __init__(self):
        """Constructor."""

        kvs_table_name = self._postgresql_raw_annotations_table()
        if kvs_table_name is None or len(kvs_table_name) == 0:
            fatal_error("Annotator's key-value store table name is not set.")

        compression_method = KeyValueStore.Compression.GZIP
        if self.__USE_BZIP:
            compression_method = KeyValueStore.Compression.BZIP2

        self.__postgresql_store = PostgreSQLStore(table=kvs_table_name, compression_method=compression_method)

        log.debug("Will read / write annotator results to PostgreSQL table: %s" % kvs_table_name)

    def __annotate_text(self, text: str) -> Union[dict, list]:
        """Fetch JSON annotation for text, decode it into dictionary / list."""

        text = decode_object_from_bytes_if_needed(text)

        if text is None:
            fatal_error("Text is None.")

        if len(text) == 0:
            # Annotators accept empty strings, but that might happen with some stories so we're just die()ing here
            raise McJSONAnnotatorException("Text is empty.")

        log.info("Annotating %d characters of text..." % len(text))

        # Trim the text because that's what the annotator will do, and if the text is empty, we want to fail early
        # without making a request to the annotator at all
        text = text.strip()

        if self.__TEXT_LENGTH_LIMIT > 0:
            text_length = len(text)
            if text_length > self.__TEXT_LENGTH_LIMIT:
                log.warning(
                    "Text length (%d) has exceeded the request text length limit (%d) so I will truncate it." %
                    (text_length, self.__TEXT_LENGTH_LIMIT,)
                )
                text = text[:self.__TEXT_LENGTH_LIMIT]

        # Make a request
        ua = UserAgent()
        ua.set_timing([1, 2, 4, 8])
        ua.set_timeout(self.__HTTP_TIMEOUT)
        ua.set_max_size(None)

        request = None
        try:
            request = self._request_for_text(text=text)
            if request is None:
                raise McJSONAnnotatorException("Returned request is None.")
        except Exception as ex:
            # Assume that this is some sort of a programming error too
            fatal_error("Unable to create annotator request for text '%s': %s" % (text, str(ex),))

        log.debug("Sending request to %s..." % request.url())
        response = ua.request(request)
        log.debug("Response received.")

        # Force UTF-8 encoding on the response because the server might not always
        # return correct "Content-Type"
        results_string = response.decoded_utf8_content()

        if not response.is_success():
            # Error; determine whether we should be blamed for making a malformed
            # request, or is it an extraction error
            log.warning("Request failed: %s" % response.decoded_content())

            if response.code() == HTTPStatus.REQUEST_TIMEOUT.value:
                # Raise on request timeouts without retrying anything because those usually mean that we posted
                # something funky to the annotator service and it got stuck
                raise McJSONAnnotatorException(
                    "The request timed out, giving up; text length: %d; text: %s" % (len(text), text,)
                )

            if response.error_is_client_side():
                # Error was generated by the user agent client code; likely didn't reach server at all (timeout,
                # unresponsive host, etc.)
                fatal_error("User agent error: %s: %s" % (response.status_line(), results_string,))

            else:

                # Error was generated by server
                http_status_code = response.code()

                if http_status_code == HTTPStatus.METHOD_NOT_ALLOWED.value \
                        or http_status_code == HTTPStatus.BAD_REQUEST.value:
                    # Not POST, empty POST
                    fatal_error('%s: %s' % (response.status_line(), results_string,))

                elif http_status_code == HTTPStatus.INTERNAL_SERVER_ERROR.value:
                    # Processing error -- raise so that the error gets caught and logged into a database
                    raise McJSONAnnotatorException(
                        'Annotator service was unable to process the download: %s' % results_string
                    )

                else:
                    # Shutdown the extractor on unconfigured responses
                    fatal_error('Unknown HTTP response: %s: %s' % (response.status_line(), results_string,))

        if results_string is None or len(results_string) == 0:
            raise McJSONAnnotatorException("Annotator returned nothing for text: %s" % text)

        log.debug("Parsing response's JSON...")
        results = None
        try:
            results = decode_json(results_string)
            if results is None:
                raise McJSONAnnotatorException("Returned JSON is None.")
        except Exception as ex:
            # If the JSON is invalid, it's probably something broken with the remote service, so that's why whe do
            # fatal_error() here
            fatal_error("Unable to parse JSON response: %s\nJSON string: %s" % (str(ex), results_string,))
        log.debug("Done parsing response's JSON.")

        response_is_valid = False
        try:
            response_is_valid = self._fetched_annotation_is_valid(results)
        except Exception as ex:
            fatal_error(
                "Unable to determine whether response is valid: %s\nJSON string: %s" % (str(ex), results_string)
            )
        if not response_is_valid:
            fatal_error("Annotator response is invalid for JSON string: %s" % results_string)

        try:
            results = self._postprocess_fetched_annotation(results)
            if results is None:
                raise McJSONAnnotatorException("Annotation is None after postprocessing.")
        except Exception as ex:
            fatal_error("Unable to postprocess fetched response: %s\nJSON string: %s" % (str(ex), results_string))

        log.info("Done annotating %d characters of text." % len(text))

        return results

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

    def annotate_and_store_for_story(self, db: DatabaseHandler, stories_id: int) -> None:
        """Run the annotation for the story, store results in key-value store."""

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        stories_id = int(stories_id)

        if self.story_is_annotated(db=db, stories_id=stories_id):
            log.warning("Story %d is already annotated, so I will overwrite it." % stories_id)

        if not story_is_english_and_has_sentences(db=db, stories_id=stories_id):
            log.warning("Story %d is not annotatable." % stories_id)
            return

        story_sentences = db.query("""
            SELECT story_sentences_id, sentence_number, sentence
            FROM story_sentences
            WHERE stories_id = %(stories_id)s
            ORDER BY sentence_number
        """, {'stories_id': stories_id}).hashes()

        if story_sentences is None:
            raise McJSONAnnotatorException("Unable to fetch story sentences for story %s." % stories_id)

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Perl
        if isinstance(story_sentences, dict):
            story_sentences = [story_sentences]

        log.info("Annotating story's %d concatenated sentences..." % stories_id)

        sentences_concat_text = ' '.join(s['sentence'] for s in story_sentences)
        annotation = self.__annotate_text(sentences_concat_text)
        if annotation is None:
            raise McJSONAnnotatorException(
                "Unable to annotate story sentences concatenation for story %d." % stories_id)

        json_annotation = None
        try:
            json_annotation = encode_json(annotation)
            if json_annotation is None:
                raise McJSONAnnotatorException("JSON annotation is None for annotation %s." % str(annotation))
        except Exception as ex:
            fatal_error("Unable to encode annotation to JSON: %s\nAnnotation: %s" % (str(ex), str(annotation)))

        log.info("Done annotating story's %d concatenated sentences." % stories_id)

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
            raise McJSONAnnotatorException("Fetched annotation is undefined or empty for story %d." % stories_id)

        json = json.decode('utf-8')

        try:
            annotation = decode_json(json)
            if annotation is None:
                raise McJSONAnnotatorException("Annotation is None after decoding from JSON.")
        except Exception as ex:
            raise McJSONAnnotatorException(
                "Unable to parse annotation JSON for story %d: %s\nString JSON: %s" % (stories_id, str(ex), json,)
            )

        try:
            annotation = self._preprocess_stored_annotation(annotation)
            if annotation is None:
                raise McJSONAnnotatorException("Annotation is None after preprocessing.")
        except Exception as ex:
            fatal_error(
                "Unable to preprocess stored annotation for story %d: %s\nString JSON: %s" %
                (stories_id, str(ex), json,)
            )

        return annotation

    @staticmethod
    def __strip_linebreaks_and_whitespace(string: str) -> str:
        """Strip linebreaks and whitespaces for tag / tag set name (tag name can't contain linebreaks)."""

        string = re.sub(r"[\r\n]", " ", string)
        string = re.sub(r"\s\s*", " ", string)
        string = string.strip()

        return string

    def update_tags_for_story(self, db: DatabaseHandler, stories_id: int) -> None:
        """Add version, country and story tags for story."""

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        stories_id = int(stories_id)

        annotation = self.fetch_annotation_for_story(db=db, stories_id=stories_id)
        if annotation is None:
            raise McJSONAnnotatorException("Unable to fetch annotation for story %d" % stories_id)

        tags = None
        try:
            tags = self._tags_for_annotation(annotation)
        except Exception as ex:
            # Programming error (should at least return an empty list)
            fatal_error("Unable to fetch tags for story %d: %s" % (stories_id, str(ex),))

        if tags is None:
            raise McJSONAnnotatorException("Returned tags is None for story %d." % stories_id)

        log.debug("Tags for story %d: %s" % (stories_id, str(tags),))

        db.begin()

        unique_tag_sets_names = set()
        for tag in tags:
            tag_sets_name = self.__strip_linebreaks_and_whitespace(tag.tag_sets_name)
            unique_tag_sets_names.add(tag_sets_name)

        # Delete old tags the story might have under a given tag set
        db.query("""
            DELETE FROM stories_tags_map
            WHERE stories_id = %(stories_id)s
              AND tags_id IN (
                SELECT tags_id
                FROM tags
                WHERE tag_sets_id IN (
                  SELECT tag_sets_id
                  FROM tag_sets
                  WHERE name = ANY(%(tag_sets_names)s)
                )
              )
        """, {'stories_id': stories_id, 'tag_sets_names': list(unique_tag_sets_names)})

        for tag in tags:
            tag_sets_name = self.__strip_linebreaks_and_whitespace(tag.tag_sets_name)
            tags_name = self.__strip_linebreaks_and_whitespace(tag.tags_name)

            # Not using find_or_create() because tag set / tag might already exist
            # with slightly different label / description

            # Find or create a tag set
            db_tag_set = db.select(table='tag_sets', what_to_select='*', condition_hash={'name': tag_sets_name}).hash()
            if db_tag_set is None:
                db.query("""
                    INSERT INTO tag_sets (name, label, description)
                    VALUES (%(name)s, %(label)s, %(description)s)
                    ON CONFLICT (name) DO NOTHING
                """, {
                    'name': tag_sets_name,
                    'label': tag.tag_sets_label,
                    'description': tag.tag_sets_description
                })
                db_tag_set = db.select(table='tag_sets',
                                       what_to_select='*',
                                       condition_hash={'name': tag_sets_name}).hash()
            tag_sets_id = int(db_tag_set['tag_sets_id'])

            # Find or create tag
            db_tag = db.select(table='tags', what_to_select='*', condition_hash={
                'tag_sets_id': tag_sets_id,
                'tag': tags_name,
            }).hash()
            if db_tag is None:
                db.query("""
                    INSERT INTO tags (tag_sets_id, tag, label, description)
                    VALUES (%(tag_sets_id)s, %(tag)s, %(label)s, %(description)s)
                    ON CONFLICT (tag, tag_sets_id) DO NOTHING
                """, {
                    'tag_sets_id': tag_sets_id,
                    'tag': tags_name,
                    'label': tag.tags_label,
                    'description': tag.tags_description,
                })
                db_tag = db.select(table='tags', what_to_select='*', condition_hash={
                    'tag_sets_id': tag_sets_id,
                    'tag': tags_name,
                }).hash()
            tags_id = int(db_tag['tags_id'])

            # Assign story to tag (if no such mapping exists yet)
            #
            # (partitioned table's INSERT trigger will take care of conflicts)
            #
            # Not using db.create() because it tests last_inserted_id, and on duplicates there would be no such
            # "last_inserted_id" set.
            db.query("""
                INSERT INTO stories_tags_map (stories_id, tags_id)
                VALUES (%(stories_id)s, %(tags_id)s)
            """, {
                'stories_id': stories_id,
                'tags_id': tags_id,
            })

        db.commit()
