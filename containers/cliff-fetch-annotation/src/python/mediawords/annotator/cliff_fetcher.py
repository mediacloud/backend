from typing import Union

from mediawords.annotator.cliff_store import CLIFFAnnotatorStore
from mediawords.annotator.fetcher import JSONAnnotationFetcher, McJSONAnnotationFetcherException
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent import Request

from mediawords.util.config.cliff_fetcher import CLIFFFetcherConfig

log = create_logger(__name__)


class CLIFFAnnotatorFetcher(JSONAnnotationFetcher):
    """CLIFF annotator."""

    def __init__(self, fetcher_config: CLIFFFetcherConfig = None):

        self.__fetcher_config = fetcher_config
        if not self.__fetcher_config:
            self.__fetcher_config = CLIFFFetcherConfig()

        store = CLIFFAnnotatorStore()
        super().__init__(annotation_store=store)

    def _request_for_text(self, text: str) -> Request:

        text = decode_object_from_bytes_if_needed(text)

        # CLIFF annotator URL
        url = self.__fetcher_config.annotator_url()
        if url is None:
            raise McJSONAnnotationFetcherException("Unable to determine CLIFF annotator URL to use.")

        request = Request(method='POST', url=url)
        request.set_content_type('application/x-www-form-urlencoded; charset=utf-8')
        request.set_content({'q': text})

        return request

    def _fetched_annotation_is_valid(self, annotation: Union[dict, list]) -> bool:

        annotation = decode_object_from_bytes_if_needed(annotation)

        if annotation is None:
            log.warning("Annotation is None.")
            return False

        if not isinstance(annotation, dict):
            log.warning("Annotation is not dict: %s" % str(annotation))
            return False

        if 'status' not in annotation:
            log.warning("Annotation doesn't have 'status' key: %s" % str(annotation))
            return False

        if annotation['status'] != 'ok':
            log.warning("Annotation's status is not 'ok': %s" % str(annotation))
            return False

        if 'results' not in annotation:
            log.warning("Annotation doesn't have 'results' key: %s" % str(annotation))
            return False

        if not isinstance(annotation['results'], dict):
            log.warning("Annotation's results is not dict: %s" % str(annotation))
            return False

        return True
