from typing import Union, List

from mediawords.annotator.tagger import JSONAnnotationTagger, McJSONAnnotationTaggerException
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from nytlabels_base.nyt_labels_store import NYTLabelsAnnotatorStore
from nytlabels_update_story_tags.config import NYTLabelsTaggerConfig

log = create_logger(__name__)


class NYTLabelsTagger(JSONAnnotationTagger):
    """NYT labels tagger."""

    # NYTLabels version tag set
    __NYTLABELS_VERSION_TAG_SET = 'nyt_labels_version'

    # Story will be tagged with labels for which the score is above this threshold
    __NYTLABELS_SCORE_THRESHOLD = 0.2

    def __init__(self):

        store = NYTLabelsAnnotatorStore()
        super().__init__(annotation_store=store)

    def _tags_for_annotation(self, annotation: Union[dict, list]) -> List[JSONAnnotationTagger.Tag]:

        annotation = decode_object_from_bytes_if_needed(annotation)

        nytlabels_labels_tag_set = NYTLabelsTaggerConfig.tag_set()
        if nytlabels_labels_tag_set is None:
            raise McJSONAnnotationTaggerException("NYTLabels labels tag set is unset in configuration.")

        nytlabels_version_tag = NYTLabelsTaggerConfig.version_tag()
        if nytlabels_version_tag is None:
            raise McJSONAnnotationTaggerException("NYTLabels version tag is unset in configuration.")

        tags = list()

        tags.append(JSONAnnotationTagger.Tag(tag_sets_name=self.__NYTLABELS_VERSION_TAG_SET,
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
                    tags.append(JSONAnnotationTagger.Tag(tag_sets_name=nytlabels_labels_tag_set,
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
