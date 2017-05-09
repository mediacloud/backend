from mediawords.tagging import config, TAG_BY_STRING_FORMAT
from mediameter.cliff import Cliff
from mediawords.util.log import create_logger

# The huge tag set that has one tag for each place we've identified in any story
GEONAMES_TAG_SET_ID = 1011
GEONAMES_TAG_SET_NAME = 'mc-geocoder@media.mit.edu'
GEONAMES_TAG_PREFIX = 'geonames_'
GEONAMES_TAG_FORMAT = GEONAMES_TAG_PREFIX+"{}"

# The tag set that holds one tag for each version of the geocoder we use
GEOCODER_VERSION_TAG_SET_ID = 1937
GEOCODER_VERSION_TAG_SET_NAME = 'geocoder_version'

# The tag applied to any stories processed with CLIFF-CLAVIN v2.3.0
CLIFF_CLAVIN_2_3_0_TAG_ID = 9353691
CLIFF_CLAVIN_2_3_0_TAG = 'cliff_clavin_v2.3.0'

l = create_logger(__name__)

# this is a lightweight client that only holds the connection information as state, so using it
# as a singleton here instead of instantiating for each request seems reasonable
cliff_server = Cliff(config.get('geotags', 'cliff_host'), config.get('geotags', 'cliff_port'))


class McGeoTaggingException(Exception):
    """Exception thrown on NYT tagger's (hard) failures."""
    pass


def tags_for_text(story_text):
    """Asks CLIFF for places in a story. Return list of tags or raise exception on error."""
    # Do the tagging, retry on soft failures yourself, etc.
    tags = [CLIFF_CLAVIN_2_3_0_TAG_ID]
    try:
        cliff_results = cliff_server.parseText(story_text)
        if cliff_results['status'] == cliff_server.STATUS_OK:
            # add a tag for each country the story is about
            if 'countries' in cliff_results['results']['places']['focus']:
                for country in cliff_results['results']['places']['focus']['countries']:
                    tag_name = GEONAMES_TAG_FORMAT.format(country['id'])
                    tags.append(TAG_BY_STRING_FORMAT.format(GEONAMES_TAG_SET_NAME, tag_name))
            # add a tag for each state the story is about
            if 'states' in cliff_results['results']['places']['focus']:
                for state in cliff_results['results']['places']['focus']['states']:
                    tag_name = GEONAMES_TAG_FORMAT.format(state['id'])
                    tags.append(TAG_BY_STRING_FORMAT.format(GEONAMES_TAG_SET_NAME, tag_name))
            l.debug("identified {} story about tags".format(len(tags)))
        else:
            # cliff_server had an error :-()
            l.warn("CLIFF returned error {}".format(cliff_results['details']))
    except Exception as e:
        # something really bad happened
        raise McGeoTaggingException(e)
    return tags
