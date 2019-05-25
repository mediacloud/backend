import pytest

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium
from topics_base.media import get_unique_medium_name, McTopicMediaUniqueException


def test_get_unique_media_name():
    """Test get_unique_media_name()."""
    db = connect_to_db()

    num_media = 5
    [create_test_medium(db, str(i)) for i in range(num_media)]
    media = db.query("select * from media order by media_id").hashes()

    assert get_unique_medium_name(db, ['UNIQUE']) == 'UNIQUE'

    media_names = [m['name'] for m in media]
    with pytest.raises(McTopicMediaUniqueException):
        get_unique_medium_name(db, media_names)

    assert get_unique_medium_name(db, media_names + ['UNIQUE']) == 'UNIQUE'
