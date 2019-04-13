from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium
# noinspection PyProtectedMember
from mediawords.tm.media import _update_media_normalized_urls
from mediawords.util.url import normalize_url_lossy


def test_update_media_normalized_urls():
    """Test _update_media_normalized_urls()."""
    db = connect_to_db()

    [create_test_medium(db, str(i)) for i in range(5)]

    _update_media_normalized_urls(db)

    media = db.query("select * from media").hashes()
    for medium in media:
        expected_nu = normalize_url_lossy(medium['url'])
        assert (medium['url'] == expected_nu)
