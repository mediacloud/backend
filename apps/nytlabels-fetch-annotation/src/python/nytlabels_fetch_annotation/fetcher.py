from typing import Union

from mediawords.annotator.fetcher import JSONAnnotationFetcher, McJSONAnnotationFetcherException
from mediawords.util.parse_json import encode_json
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent import Request
from nytlabels_base.nyt_labels_store import NYTLabelsAnnotatorStore
from nytlabels_fetch_annotation.config import NYTLabelsFetcherConfig

log = create_logger(__name__)


class NYTLabelsAnnotatorFetcher(JSONAnnotationFetcher):
    """NYT labels annotation fetcher."""

    _ENABLED_MODEL = 'descriptors600'

    def __init__(self, fetcher_config: NYTLabelsFetcherConfig = None):

        self.__fetcher_config = fetcher_config
        if not self.__fetcher_config:
            self.__fetcher_config = NYTLabelsFetcherConfig()

        store = NYTLabelsAnnotatorStore()
        super().__init__(annotation_store=store)

    def _request_for_text(self, text: str) -> Request:

        text = decode_object_from_bytes_if_needed(text)

        url = self.__fetcher_config.annotator_url()
        if url is None:
            raise McJSONAnnotationFetcherException("Unable to determine NYLabels annotator URL to use.")

        # Create JSON request
        log.debug("Converting text to JSON request...")
        try:
            text_json = encode_json({'text': text, 'models': [self._ENABLED_MODEL]})
        except Exception as ex:
            # Not critical, might happen to some stories, no need to shut down the annotator
            raise McJSONAnnotationFetcherException(
                "Unable to encode text to a JSON request: %(exception)s\nText: %(text)s" % {
                    'exception': str(ex),
                    'text': text,
                }
            )
        log.debug("Done converting text to JSON request.")

        request = Request(method='POST', url=url)
        request.set_content_type('application/json; charset=utf-8')
        request.set_content(text_json)

        return request

    # noinspection PyMethodMayBeStatic
    def _fetched_annotation_is_valid(self, annotation: Union[dict, list]) -> bool:

        annotation = decode_object_from_bytes_if_needed(annotation)

        if annotation is None:
            log.warning("Annotation is None.")
            return False

        if not isinstance(annotation, dict):
            log.warning("Annotation is not dict: %s" % str(annotation))
            return False

        if self._ENABLED_MODEL not in annotation:
            log.warning(f"Annotation doesn't have '{self._ENABLED_MODEL}' key: {annotation}")
            return False

        return True
