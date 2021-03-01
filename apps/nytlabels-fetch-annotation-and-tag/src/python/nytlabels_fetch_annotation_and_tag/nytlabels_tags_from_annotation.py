from typing import Union, List

from mediawords.tag_from_annotation.fetch_and_tag import TagsFromJSONAnnotation, McTagsFromJSONAnnotationException
from mediawords.util.log import create_logger
from mediawords.util.parse_json import encode_json
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.web.user_agent import Request
from nytlabels_fetch_annotation_and_tag.config import NYTLabelsTagsFromAnnotationConfig

log = create_logger(__name__)


class NYTLabelsTagsFromAnnotation(TagsFromJSONAnnotation):
    """Fetches NYT labels annotation and uses it to generate/store story tags."""

    # Specific model to run the input text against
    _ENABLED_MODEL = 'descriptors600'

    # NYTLabels version tag set
    __NYTLABELS_VERSION_TAG_SET = 'nyt_labels_version'

    # Story will be tagged with labels for which the score is above this threshold
    __NYTLABELS_SCORE_THRESHOLD = 0.2

    def __init__(self, tagger_config: NYTLabelsTagsFromAnnotationConfig = None):

        self.__tagger_config = tagger_config
        if not self.__tagger_config:
            self.__tagger_config = NYTLabelsTagsFromAnnotationConfig()

    def _request_for_text(self, text: str) -> Request:

        text = decode_object_from_bytes_if_needed(text)

        url = self.__tagger_config.annotator_url()
        if url is None:
            raise McTagsFromJSONAnnotationException("Unable to determine NYLabels annotator URL to use.")

        # Create JSON request
        log.debug("Converting text to JSON request...")
        try:
            text_json = encode_json({'text': text, 'models': [self._ENABLED_MODEL]})
        except Exception as ex:
            # Not critical, might happen to some stories, no need to shut down the annotator
            raise McTagsFromJSONAnnotationException(
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

    def _tags_for_annotation(self, annotation: Union[dict, list]) -> List[TagsFromJSONAnnotation.Tag]:

        annotation = decode_object_from_bytes_if_needed(annotation)

        nytlabels_labels_tag_set = NYTLabelsTagsFromAnnotationConfig.tag_set()
        if nytlabels_labels_tag_set is None:
            raise McTagsFromJSONAnnotationException("NYTLabels labels tag set is unset in configuration.")

        nytlabels_version_tag = NYTLabelsTagsFromAnnotationConfig.version_tag()
        if nytlabels_version_tag is None:
            raise McTagsFromJSONAnnotationException("NYTLabels version tag is unset in configuration.")

        tags = list()

        tags.append(TagsFromJSONAnnotation.Tag(tag_sets_name=self.__NYTLABELS_VERSION_TAG_SET,
                                               tag_sets_label=self.__NYTLABELS_VERSION_TAG_SET,
                                               tag_sets_description='NYTLabels version the story was tagged with',
                                               tags_name=nytlabels_version_tag,
                                               tags_label=nytlabels_version_tag,
                                               tags_description="Story was tagged with '%s'" % nytlabels_version_tag))

        descriptors = annotation.get(self._ENABLED_MODEL, None)
        if descriptors is not None and len(descriptors) > 0:

            for descriptor in descriptors:

                label = descriptor['label']
                score = float(descriptor['score'])

                if score > self.__NYTLABELS_SCORE_THRESHOLD:
                    tags.append(TagsFromJSONAnnotation.Tag(tag_sets_name=nytlabels_labels_tag_set,
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
