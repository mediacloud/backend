#!/usr/bin/env py.test

import pytest

from mediawords.db import connect_to_db
from mediawords.tm.media import get_unique_medium_url, URL_SPIDERED_SUFFIX, McTopicMediaUniqueException
from mediawords.test.db.create import create_test_medium


def test_get_unique_media_url():
    """Test get_unique_media_url()."""
    db = connect_to_db()

    num_media = 5
    [create_test_medium(db, str(i)) for i in range(num_media)]
    media = db.query("select * from media order by media_id").hashes()

    assert get_unique_medium_url(db, ['UNIQUE']) == 'UNIQUE'

    media_urls = [m['url'] for m in media]

    expected_url = media[0]['url'] + URL_SPIDERED_SUFFIX
    assert get_unique_medium_url(db, media_urls) == expected_url

    db.query(
        "insert into media (name, url) select name || %(a)s, url || %(a)s from media",
        {'a': URL_SPIDERED_SUFFIX})

    with pytest.raises(McTopicMediaUniqueException):
        get_unique_medium_url(db, media_urls)

    assert get_unique_medium_url(db, media_urls + ['UNIQUE']) == 'UNIQUE'
