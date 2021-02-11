import pytest

from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed

from crawler_fetcher.engine import handler_for_download
from crawler_fetcher.exceptions import McCrawlerFetcherSoftError


def test_invalid_feed_url():
    """Try fetching a funky URL."""
    db = connect_to_db()

    test_medium = create_test_medium(db=db, label='test')
    test_feed = create_test_feed(db=db, label='test', medium=test_medium)

    download = db.create(table='downloads', insert_hash={
        'url': 'file:///etc/passwd',
        'host': 'localhost',
        'type': 'feed',
        'state': 'pending',
        'priority': 0,
        'sequence': 1,
        'feeds_id': test_feed['feeds_id'],
    })

    handler = handler_for_download(db=db, download=download)

    # Invalid URL should be a soft exception
    with pytest.raises(McCrawlerFetcherSoftError):
        handler.fetch_download(db=db, download=download)
