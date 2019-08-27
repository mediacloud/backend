from mediawords.db import DatabaseHandler
from mediawords.util.url import get_url_host


def create_download_for_new_story(db: DatabaseHandler, story: dict, feed: dict) -> dict:
    """Create and return download object in database for the new story."""

    download = {
        'feeds_id': feed['feeds_id'],
        'stories_id': story['stories_id'],
        'url': story['url'],
        'host': get_url_host(story['url']),
        'type': 'content',
        'sequence': 1,
        'state': 'success',
        'path': 'content:pending',
        'priority': 1,
        'extracted': 'f'
    }

    download = db.create('downloads', download)

    return download
