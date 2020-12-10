import abc
import re
from http import HTTPStatus
import time
from typing import Union, List

from furl import furl

from mediawords.db import DatabaseHandler
from mediawords.dbi.stories.postprocess import story_is_english_and_has_sentences
from mediawords.util.parse_json import decode_json
from mediawords.util.log import create_logger
from mediawords.util.network import wait_for_tcp_port_to_open
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error
from mediawords.util.web.user_agent import Request, UserAgent

log = create_logger(__name__)


class McTagsFromJSONAnnotationException(Exception):
    """JSON tags-from-annotation exception."""
    pass


class TagsFromJSONAnnotation(metaclass=abc.ABCMeta):
    """Abstract class to generate tags from fetched JSON annotation."""

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

    # ---

    # HTTP timeout for annotator
    __HTTP_TIMEOUT = 600

    # Requested text length limit (0 for no limit)
    __TEXT_LENGTH_LIMIT = 50 * 1024

    __ANNOTATOR_SERVICE_TIMEOUT = 60 * 5
    """Seconds to wait for the nytlabels-annotator service to start.

    Wait for five minutes as those workers might take their time to load big heavy
    models (e.g. Google News word2vec model in NYTLabels annotator).
    """

    @staticmethod
    def __strip_linebreaks_and_whitespace(string: str) -> str:
        """Strip linebreaks and whitespaces for tag / tag set name (tag name can't contain linebreaks)."""

        string = re.sub(r"[\r\n]", " ", string)
        string = re.sub(r"\s\s*", " ", string)
        string = string.strip()

        return string

    def __annotate_text(self, text: str) -> Union[dict, list]:
        """Takes text, fetches JSON annotation, decodes it into dictionary / list."""

        text = decode_object_from_bytes_if_needed(text)

        if text is None:
            fatal_error("Text is None.")

        if len(text) == 0:
            # Annotators accept empty strings, but that might happen with some stories so we're just die()ing here
            raise McTagsFromJSONAnnotationException("Text is empty.")

        log.info(f"Annotating {len(text)} characters of text...")

        # Trim the text because that's what the annotator will do, and if the text is empty, we want to fail early
        # without making a request to the annotator at all
        text = text.strip()

        if self.__TEXT_LENGTH_LIMIT > 0:
            text_length = len(text)
            if text_length > self.__TEXT_LENGTH_LIMIT:
                log.warning(
                    f"Text length ({text_length}) has exceeded the request text length limit"
                    f"({self.__TEXT_LENGTH_LIMIT}) so I will truncate it."
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
                raise McTagsFromJSONAnnotationException("Returned request is None.")
        except Exception as ex:
            # Assume that this is some sort of a programming error too
            fatal_error(f"Unable to create annotator request for text '{text}': {ex}")

        # Wait for the service's HTTP port to become open as the service might be
        # still starting up somewhere
        uri = furl(request.url())
        hostname = str(uri.host)
        port = int(uri.port)
        assert hostname, f"URL hostname is not set for URL {request.url()}"
        assert port, f"API URL port is not set for URL {request.url()}"

        if not wait_for_tcp_port_to_open(
                port=port,
                hostname=hostname,
                retries=self.__ANNOTATOR_SERVICE_TIMEOUT,
        ):
            # Instead of throwing an exception, just crash the whole application
            # because there's no point in continuing on running it whatsoever.
            fatal_error(
                f"Annotator service at {request.url()} didn't come up in {self.__ANNOTATOR_SERVICE_TIMEOUT} seconds, "
                f"exiting..."
            )

        log.debug(f"Sending request to {request.url()}...")

        # Try requesting a few times because sometimes it throws a connection error, e.g.:
        #
        #   WARNING mediawords.util.web.user_agent: Client-side error while processing request <PreparedRequest [POST]>:
        #   ('Connection aborted.', ConnectionResetError(104, 'Connection reset by peer'))
        #   WARNING mediawords.tag_from_annotation.fetch_and_tag: Request failed: ('Connection aborted.', ConnectionResetError(104,
        #   'Connection reset by peer'))
        #   ERROR mediawords.util.process: User agent error: 400 Client-side error: ('Connection aborted.',
        #   ConnectionResetError(104, 'Connection reset by peer'))
        response = None
        retries = 60
        sleep_between_retries = 1
        for retry in range(1, retries + 1):

            if retry > 1:
                log.warning(f"Retrying ({retry} / {retries})...")

            response = ua.request(request)

            if response.is_success():
                break
            else:
                if response.error_is_client_side():
                    log.error(f"Request failed on the client side: {response.decoded_content()}")
                    time.sleep(sleep_between_retries)
                else:
                    break

        log.debug("Response received.")

        # Force UTF-8 encoding on the response because the server might not always
        # return correct "Content-Type"
        results_string = response.decoded_utf8_content()

        if not response.is_success():
            # Error; determine whether we should be blamed for making a malformed
            # request, or is it an extraction error
            log.warning(f"Request failed: {response.decoded_content()}")

            if response.code() == HTTPStatus.REQUEST_TIMEOUT.value:
                # Raise on request timeouts without retrying anything because those usually mean that we posted
                # something funky to the annotator service and it got stuck
                raise McTagsFromJSONAnnotationException(
                    f"The request timed out, giving up; text length: {len(text)}; text: {text}"
                )

            if response.error_is_client_side():
                # Error was generated by the user agent client code; likely didn't reach server at all (timeout,
                # unresponsive host, etc.)
                fatal_error(f"User agent error: {response.status_line()}: {results_string}")

            else:

                # Error was generated by server
                http_status_code = response.code()

                if http_status_code == HTTPStatus.METHOD_NOT_ALLOWED.value \
                        or http_status_code == HTTPStatus.BAD_REQUEST.value:
                    # Not POST, empty POST
                    fatal_error(f'{response.status_line()}: {results_string}')

                elif http_status_code == HTTPStatus.INTERNAL_SERVER_ERROR.value:
                    # Processing error -- raise so that the error gets caught and logged into a database
                    raise McTagsFromJSONAnnotationException(
                        f'Annotator service was unable to process the download: {results_string}'
                    )

                else:
                    # Shutdown the extractor on unconfigured responses
                    fatal_error(f'Unknown HTTP response: {response.status_line()}: {results_string}')

        if results_string is None or len(results_string) == 0:
            raise McTagsFromJSONAnnotationException(f"Annotator returned nothing for text: {text}")

        log.debug("Parsing response's JSON...")
        results = None
        try:
            results = decode_json(results_string)
            if results is None:
                raise McTagsFromJSONAnnotationException("Returned JSON is None.")
        except Exception as ex:
            # If the JSON is invalid, it's probably something broken with the remote service, so that's why whe do
            # fatal_error() here
            fatal_error(f"Unable to parse JSON response: {ex}\nJSON string: {results_string}")
        log.debug("Done parsing response's JSON.")

        response_is_valid = False
        try:
            response_is_valid = self._fetched_annotation_is_valid(results)
        except Exception as ex:
            fatal_error(
                f"Unable to determine whether response is valid: {ex}\nJSON string: {results_string}"
            )
        if not response_is_valid:
            fatal_error(f"Annotator response is invalid for JSON string: {results_string}")

        log.info(f"Done annotating {len(text)} characters of text.")

        return results

    def annotate_story(self, db: DatabaseHandler, stories_id: int) -> Union[dict, list]:
        """Get story text and generate annotation."""

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        stories_id = int(stories_id)

        if not story_is_english_and_has_sentences(db=db, stories_id=stories_id):
            log.warning(f"Story {stories_id} is not annotatable.")
            return

        story_sentences = db.query("""
            SELECT story_sentences_id, sentence_number, sentence
            FROM story_sentences
            WHERE stories_id = %(stories_id)s
            ORDER BY sentence_number
        """, {'stories_id': stories_id}).hashes()

        if story_sentences is None:
            raise McTagsFromJSONAnnotationException(f"Unable to fetch story sentences for story {stories_id}.")

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Perl
        if isinstance(story_sentences, dict):
            story_sentences = [story_sentences]

        log.info(f"Annotating story's {stories_id} concatenated sentences...")

        sentences_concat_text = ' '.join(s['sentence'] for s in story_sentences)
        annotation = self.__annotate_text(sentences_concat_text)
        if annotation is None:
            raise McTagsFromJSONAnnotationException(
                f"Unable to annotate story sentences concatenation for story {stories_id}.")
        return annotation

    def update_tags_for_story(self, db: DatabaseHandler, stories_id: int) -> None:
        """Add version, country and story tags for story."""

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        stories_id = int(stories_id)

        annotation = self.annotate_story(db=db, stories_id=stories_id)
        if annotation is None:
            raise McTagsFromJSONAnnotationException("Unable to fetch annotation for story %d" % stories_id)

        tags = None
        try:
            tags = self._tags_for_annotation(annotation)
        except Exception as ex:
            # Programming error (should at least return an empty list)
            fatal_error("Unable to fetch tags for story %d: %s" % (stories_id, str(ex),))

        if tags is None:
            raise McTagsFromJSONAnnotationException("Returned tags is None for story %d." % stories_id)

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
