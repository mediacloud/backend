from mediawords.tm.media import get_spidered_tag, SPIDERED_TAG_TAG, SPIDERED_TAG_SET
from mediawords.db import connect_to_db


def test_get_spidered_tag():
    db = connect_to_db()

    tag = get_spidered_tag(db)

    assert tag['tag'] == SPIDERED_TAG_TAG

    tag_set = db.require_by_id('tag_sets', tag['tag_sets_id'])
    assert tag_set['name'] == SPIDERED_TAG_SET

    assert get_spidered_tag(db)['tags_id'] == tag['tags_id']
