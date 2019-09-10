from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium

# noinspection PyProtectedMember
from topics_base.media import _normalized_urls_out_of_date


def test_normalized_urls_out_of_date():
    """Test _normalized_urls_out_of_date()."""
    db = connect_to_db()

    assert not _normalized_urls_out_of_date(db)

    [create_test_medium(db, str(i)) for i in range(5)]

    assert _normalized_urls_out_of_date(db)

    # noinspection SqlWithoutWhere
    db.query("update media set normalized_url = url")

    assert not _normalized_urls_out_of_date(db)

    db.query("update media set normalized_url = null where media_id in ( select media_id from media limit 1 )")

    assert _normalized_urls_out_of_date(db)

    # noinspection SqlWithoutWhere
    db.query("update media set normalized_url = url")

    assert not _normalized_urls_out_of_date(db)
