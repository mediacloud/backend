"""Parse generic posts from a csv."""

import datetime

from mediawords.util.csv import get_dicts_from_csv_string
from mediawords.util.log import create_logger
log = create_logger(__name__)


class McPostsGenericDataException(Exception):
    """exception indicating an error in the data for generic posts."""
    pass


def fetch_posts(query: str, start_date: datetime, end_date: datetime) -> list:
    """Return posts from a csv that are within the given date range."""
    all_posts = get_dicts_from_csv_string(query)

    posts = []
    for p in all_posts:
        if p['publish_date'] >= str(start_date) and p['publish_date'] <= str(end_date):
            posts.append(p)

    required_fields = ['content', 'author', 'channel', 'content', 'publish_date', 'post_id']
    for post in posts:
        for field in required_fields:
            if field not in post:
                raise(McPostsGenericDataException("Missing required field: %s" % field))

        post['data'] = {}

    return posts
