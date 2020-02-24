import hashlib
from typing import List, Dict, Any

from mediawords.db import DatabaseHandler
from mediawords.util.perl import decode_object_from_bytes_if_needed


def _stories_checksum(stories: List[Dict[str, Any]]) -> str:
    """Generate a checksum from a list of stories based on their URLs."""
    stories = decode_object_from_bytes_if_needed(stories)

    story_urls = [story.get('url', '') for story in stories]
    story_url_concat = '|'.join(story_urls)
    checksum = hashlib.md5(story_url_concat.encode('utf-8')).hexdigest()

    return checksum


def stories_checksum_matches_feed(db: DatabaseHandler, feeds_id: int, stories: List[Dict[str, Any]]) -> bool:
    """
    Check whether the checksum of the concatenated URLs of the stories in the feed matches the last such checksum for
    this feed. If the checksums don't match, store the current checksum in the feed.
    """
    if isinstance(feeds_id, bytes):
        feeds_id = decode_object_from_bytes_if_needed(feeds_id)
    feeds_id = int(feeds_id)
    stories = decode_object_from_bytes_if_needed(stories)

    checksum = _stories_checksum(stories=stories)

    matches = db.query("""
        SELECT 1
        FROM feeds
        WHERE feeds_id = %(feeds_id)s
          AND last_checksum = %(checksum)s
    """, {
        'feeds_id': feeds_id,
        'checksum': checksum,
    }).flat()

    if matches:
        return True

    else:
        db.query("""
            UPDATE feeds
            SET last_checksum = %(checksum)s
            WHERE feeds_id = %(feeds_id)s
        """, {
            'feeds_id': feeds_id,
            'checksum': checksum,
        })

        return False
