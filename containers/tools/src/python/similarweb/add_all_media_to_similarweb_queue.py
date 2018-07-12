#!/usr/bin/env python3

from mediawords.db import connect_to_db, DatabaseHandler
from mediawords.job.similarweb.update_audience_data import SimilarWebUpdateAudienceDataJob
from mediawords.util.log import create_logger

log = create_logger(__name__)


def add_all_media_to_similarweb_queue(db: DatabaseHandler):
    """Add all media IDs to SimilarWeb's queue."""
    log.info("Fetching all media IDs...")
    media_ids = db.query("""
        SELECT media_id
        FROM media
        ORDER BY media_id
    """).flat()
    for media_id in media_ids:
        log.info("Adding media ID %d" % media_id)
        SimilarWebUpdateAudienceDataJob.add_to_queue(media_id=media_id)


if __name__ == "__main__":
    db = connect_to_db()
    add_all_media_to_similarweb_queue(db=db)
