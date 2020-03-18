import abc
from http import HTTPStatus
from typing import Union

from furl import furl

from mediawords.annotator.store import JSONAnnotationStore
from mediawords.db import DatabaseHandler
from mediawords.dbi.stories.postprocess import story_is_english_and_has_sentences
from mediawords.util.parse_json import decode_json
from mediawords.util.log import create_logger
from mediawords.util.network import wait_for_tcp_port_to_open
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.process import fatal_error
from mediawords.util.web.user_agent import Request, UserAgent

log = create_logger(__name__)


class McJSONAnnotationFetcherException(Exception):
    """JSON annotation fetcher exception."""
    pass


class JSONAnnotationFetcher(metaclass=abc.ABCMeta):
    """Abstract JSON fetcher."""

    @abc.abstractmethod
    def _request_for_text(self, text: str) -> Request:
        """Returns Request that should be made to the annotator service to annotate a given text."""
        raise NotImplementedError

    @abc.abstractmethod
    def _fetched_annotation_is_valid(self, annotation: Union[dict, list]) -> bool:
        """Returns true if decoded response JSON is valid."""
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

    __slots__ = [
        '__annotation_store',
    ]

    def __init__(self, annotation_store: JSONAnnotationStore):
        """Constructor."""

        assert annotation_store, "Annotation store is set."
        self.__annotation_store = annotation_store

    def __annotate_text(self, text: str) -> Union[dict, list]:
        """Fetch JSON annotation for text, decode it into dictionary / list."""

        text = decode_object_from_bytes_if_needed(text)

        if text is None:
            fatal_error("Text is None.")

        if len(text) == 0:
            # Annotators accept empty strings, but that might happen with some stories so we're just die()ing here
            raise McJSONAnnotationFetcherException("Text is empty.")

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
                raise McJSONAnnotationFetcherException("Returned request is None.")
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

        response = ua.request(request)
        log.debug(f"Sending request to {request.url()}...")
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
                raise McJSONAnnotationFetcherException(
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
                    raise McJSONAnnotationFetcherException(
                        f'Annotator service was unable to process the download: {results_string}'
                    )

                else:
                    # Shutdown the extractor on unconfigured responses
                    fatal_error(f'Unknown HTTP response: {response.status_line()}: {results_string}')

        if results_string is None or len(results_string) == 0:
            raise McJSONAnnotationFetcherException(f"Annotator returned nothing for text: {text}")

        log.debug("Parsing response's JSON...")
        results = None
        try:
            results = decode_json(results_string)
            if results is None:
                raise McJSONAnnotationFetcherException("Returned JSON is None.")
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

    def annotate_and_store_for_story(self, db: DatabaseHandler, stories_id: int) -> None:
        """Run the annotation for the story, store results in key-value store."""

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Python
        if isinstance(stories_id, bytes):
            stories_id = decode_object_from_bytes_if_needed(stories_id)

        stories_id = int(stories_id)

        if self.__annotation_store.story_is_annotated(db=db, stories_id=stories_id):
            log.warning(f"Story {stories_id} is already annotated, so I will overwrite it.")

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
            raise McJSONAnnotationFetcherException(f"Unable to fetch story sentences for story {stories_id}.")

        # MC_REWRITE_TO_PYTHON: remove after rewrite to Perl
        if isinstance(story_sentences, dict):
            story_sentences = [story_sentences]

        log.info(f"Annotating story's {stories_id} concatenated sentences...")

        sentences_concat_text = ' '.join(s['sentence'] for s in story_sentences)
        annotation = self.__annotate_text(sentences_concat_text)
        if annotation is None:
            raise McJSONAnnotationFetcherException(
                f"Unable to annotate story sentences concatenation for story {stories_id}.")

        self.__annotation_store.store_annotation_for_story(db=db, stories_id=stories_id, annotation=annotation)
