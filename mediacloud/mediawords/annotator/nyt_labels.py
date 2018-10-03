from typing import Union, List

from mediawords.annotator import JSONAnnotator, McJSONAnnotatorException
from mediawords.util.config import get_config as py_get_config
from mediawords.util.parse_json import encode_json
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent import Request

log = create_logger(__name__)


class McNYTLabelsAnnotatorException(McJSONAnnotatorException):
    """NYT labels annotator exception."""
    pass


class NYTLabelsAnnotator(JSONAnnotator):
    """NYT labels annotator."""

    # NYTLabels version tag set
    __NYTLABELS_VERSION_TAG_SET = 'nyt_labels_version'

    # Story will be tagged with labels for which the score is above this threshold
    __NYTLABELS_SCORE_THRESHOLD = 0.2

    def annotator_is_enabled(self) -> bool:
        config = py_get_config()

        if config.get('nytlabels', {}).get('enabled', False):
            return True
        else:
            return False

    def _postgresql_raw_annotations_table(self) -> str:
        return 'nytlabels_annotations'

    def _request_for_text(self, text: str) -> Request:

        text = decode_object_from_bytes_if_needed(text)

        # CLIFF annotator URL
        config = py_get_config()
        url = config.get('nytlabels', {}).get('annotator_url', None)
        if url is None:
            raise McNYTLabelsAnnotatorException("Unable to determine NYTLabels annotator URL to use.")

        # Create JSON request
        log.debug("Converting text to JSON request...")
        try:
            text_json = encode_json({'text': text})
        except Exception as ex:
            # Not critical, might happen to some stories, no need to shut down the annotator
            raise McNYTLabelsAnnotatorException(
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

    def _fetched_annotation_is_valid(self, annotation: Union[dict, list]) -> bool:

        annotation = decode_object_from_bytes_if_needed(annotation)

        if annotation is None:
            log.warning("Annotation is None.")
            return False

        if not isinstance(annotation, dict):
            log.warning("Annotation is not dict: %s" % str(annotation))
            return False

        if 'descriptors600' not in annotation:
            log.warning("Annotation doesn't have 'descriptors600' key: %s" % str(annotation))
            return False

        return True

    def _tags_for_annotation(self, annotation: Union[dict, list]) -> List[JSONAnnotator.Tag]:

        annotation = decode_object_from_bytes_if_needed(annotation)

        config = py_get_config()

        nytlabels_config = config.get('nytlabels', None)
        if nytlabels_config is None:
            raise McNYTLabelsAnnotatorException("NYTLabels is not configured.")

        nytlabels_labels_tag_set = nytlabels_config.get('nytlabels_labels_tag_set', None)
        if nytlabels_labels_tag_set is None:
            raise McNYTLabelsAnnotatorException("NYTLabels labels tag set is unset in configuration.")

        nytlabels_version_tag = nytlabels_config.get('nytlabels_version_tag', None)
        if nytlabels_version_tag is None:
            raise McNYTLabelsAnnotatorException("NYTLabels version tag is unset in configuration.")

        tags = list()

        tags.append(JSONAnnotator.Tag(tag_sets_name=self.__NYTLABELS_VERSION_TAG_SET,
                                      tag_sets_label=self.__NYTLABELS_VERSION_TAG_SET,
                                      tag_sets_description='NYTLabels version the story was tagged with',
                                      tags_name=nytlabels_version_tag,
                                      tags_label=nytlabels_version_tag,
                                      tags_description="Story was tagged with '%s'" % nytlabels_version_tag))

        descriptors600 = annotation.get('descriptors600', None)
        if descriptors600 is not None and len(descriptors600) > 0:

            for descriptor in descriptors600:

                label = descriptor['label']
                score = float(descriptor['score'])

                if score > self.__NYTLABELS_SCORE_THRESHOLD:
                    tags.append(JSONAnnotator.Tag(tag_sets_name=nytlabels_labels_tag_set,
                                                  tag_sets_label=nytlabels_labels_tag_set,
                                                  tag_sets_description='NYTLabels labels',

                                                  # e.g. "hurricanes and tropical storms"
                                                  tags_name=label,
                                                  tags_label=label,
                                                  tags_description=label))

                else:
                    log.debug(("Skipping label '%(label)s' because its score %(score)2.6f"
                               "is lower than the threshold %(threshold)2.6f" % {
                                   'label': label,
                                   'score': score,
                                   'threshold': self.__NYTLABELS_SCORE_THRESHOLD,
                               }))

        return tags
