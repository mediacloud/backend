import nose
from nose.tools import assert_raises

import mediawords.tagging.geotags as geotags
from mediameter.cliff import Cliff

TEST_STORY_TWO_PLACES = "This is about New Delhi.  It is also about Accra."
TEST_STORY_ONE_PLACE = "This is a story about London."
TEST_STORY_NO_PLACES = "This isn't about any places at all."


def test_story_parsing():
    tags = geotags.tags_for_text(TEST_STORY_NO_PLACES)
    assert len(tags) == 1

    tags = geotags.tags_for_text(TEST_STORY_ONE_PLACE)
    assert len(tags) == 3
    assert geotags.CLIFF_CLAVIN_2_3_0_TAG_ID in tags
    assert 'mc-geocoder@media.mit.edu:geonames_2635167' in tags
    assert 'mc-geocoder@media.mit.edu:geonames_6269131' in tags

    tags = geotags.tags_for_text(TEST_STORY_TWO_PLACES)
    assert len(tags) == 5
    assert geotags.CLIFF_CLAVIN_2_3_0_TAG_ID in tags
    assert 'mc-geocoder@media.mit.edu:geonames_1269750' in tags
    assert 'mc-geocoder@media.mit.edu:geonames_2300660' in tags
    assert 'mc-geocoder@media.mit.edu:geonames_1273293' in tags
    assert 'mc-geocoder@media.mit.edu:geonames_2300569' in tags


def test_no_service():
    # the trick here is to point at a non-existant server and make sure it fails with an Exception
    geotags.cliff_server = Cliff('http://www.localhost', '12345')
    assert_raises(geotags.McGeoTaggingException, geotags.tags_for_text, 'NONEXISTENT_LABEL')

if __name__ == "__main__":
    nose.main()
