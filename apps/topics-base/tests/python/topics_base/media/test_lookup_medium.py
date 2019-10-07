import pytest

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium
from topics_base.media import lookup_medium, McTopicMediaException


def test_lookup_medium():
    """Test lookup_medium()."""
    db = connect_to_db()

    num_media = 5
    [create_test_medium(db, str(i)) for i in range(num_media)]

    # dummy call to lookup_medium to set normalized_urls
    lookup_medium(db, 'foo', 'foo')

    media = db.query("select * from media order by media_id").hashes()

    assert lookup_medium(db, 'FAIL', 'FAIL') is None

    for i in range(num_media):
        assert lookup_medium(db, media[i]['url'], 'IGNORE') == media[i]
        assert lookup_medium(db, media[i]['url'].upper(), 'IGNORE') == media[i]
        assert lookup_medium(db, 'IGNORE', media[i]['name']) == media[i]
        assert lookup_medium(db, 'IGNORE', media[i]['name'].upper()) == media[i]

    db.query(
        "update media set dup_media_id = %(a)s where media_id = %(b)s",
        {'a': media[1]['media_id'], 'b': media[2]['media_id']})
    db.query(
        "update media set dup_media_id = %(a)s where media_id = %(b)s",
        {'a': media[2]['media_id'], 'b': media[3]['media_id']})

    assert lookup_medium(db, media[3]['url'], 'IGNORE') == media[1]

    db.query(
        "update media set foreign_rss_links = 't' where media_id = %(a)s",
        {'a': media[1]['media_id']})

    with pytest.raises(McTopicMediaException):
        lookup_medium(db, media[3]['url'], 'IGNORE')

    db.query(
        "update media set dup_media_id = %(a)s where media_id = %(b)s",
        {'a': media[3]['media_id'], 'b': media[1]['media_id']})

    with pytest.raises(McTopicMediaException):
        lookup_medium(db, media[3]['url'], 'IGNORE')
