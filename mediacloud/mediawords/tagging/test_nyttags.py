import nose
from nose.tools import assert_raises

import mediawords.tagging.nyttags as nyttags
import mediawords.tagging

TEST_STORY_NOTHING = "This is about nothing at all."
TEST_STORY_EDUCATION = "This is a great story about education and learning."


def test_story_parsing():
    tags = nyttags.tags_for_text(TEST_STORY_NOTHING)
    assert len(tags) == 2
    assert nyttags.NYT_LABELER_1_0_0_TAG_ID in tags
    assert 'nyt_labels:quotation of the day' in tags

    tags = nyttags.tags_for_text(TEST_STORY_EDUCATION)
    assert len(tags) == 2
    assert nyttags.NYT_LABELER_1_0_0_TAG_ID in tags
    assert 'nyt_labels:education and schools' in tags


def test_no_service():
    # the trick here is to point at a non-existent server and make sure it fails with an Exception
    mediawords.tagging.nyttags.server_url = "{}:{}/predict.json".format('http://www.localhost', '12345')
    assert_raises(nyttags.McNytTaggingException, nyttags.tags_for_text, TEST_STORY_NOTHING)


if __name__ == "__main__":
    nose.main()
