import requests

from mediawords.tagging import config, TAG_BY_STRING_FORMAT
from mediawords.util.log import create_logger


# The tag set that holds one tag for each version of the labeller service we use
NYT_LABELS_VERSION_TAG_SET_ID = 1964
NYT_LABELS_VERSION_TAG_SET_NAME = 'nyt_labels_version'
# The tag applied to any stories processed with NYT labeller v1.0
NYT_LABELER_1_0_0_TAG_ID = 9360669

# The big tag set that has one tag for each descriptor
NYT_LABELS_TAG_SET_ID = 1963
NYT_LABELS_TAG_SET_NAME = 'nyt_labels'

# subjectively determined based on random experimentation
RELEVANCE_THRESHOLD = 0.20

l = create_logger(__name__)

server_url = "{}:{}/predict.json".format(config.get('nyttags', 'labeller_host'),
                                         config.get('nyttags', 'labeller_port'))


class McNytTaggingException(Exception):
    """Exception thrown on NYT tagger's (hard) failures."""
    pass


def tags_for_text(story_text):
    """Asks labeller for descriptors, returns list of tags or throws exception."""
    tags = [NYT_LABELER_1_0_0_TAG_ID]
    try:
        results = _labels_for_text(story_text)
        # only tag it with ones that score really high
        descriptors = results['descriptors600']
        for label in descriptors:
            if float(label['score']) > RELEVANCE_THRESHOLD:
                tag_name = label['label']
                tags.append(TAG_BY_STRING_FORMAT.format(NYT_LABELS_TAG_SET_NAME, tag_name))
    except Exception as e:
        # something really bad happened
        raise McNytTaggingException(e)
    return tags


def _labels_for_text(text):
    r = requests.post(server_url, json={'text': text})
    return r.json()
