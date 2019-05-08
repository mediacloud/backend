#!/usr/bin/env python3

from mediawords.db import connect_to_db, DatabaseHandler
from mediawords.job import JobBroker
from mediawords.util.log import create_logger

log = create_logger(__name__)


def add_all_media_to_sitemap_queue(db: DatabaseHandler):
    """Add all media IDs to XML sitemap fetching queue."""
    log.info("Fetching all media IDs...")
    media_ids = db.query("""
        SELECT media_id
        FROM media
        ORDER BY media_id
    """).flat()
    for media_id in media_ids:
        log.info("Adding media ID %d" % media_id)
        JobBroker(queue_name='MediaWords::Job::Sitemap::FetchMediaPages').add_to_queue(media_id=media_id)


def add_us_media_to_sitemap_queue():
    us_media_ids = [
        104828, 1089, 1092, 1095, 1098, 1101, 1104, 1110, 1145, 1149, 1150, 14, 15, 1747, 1750, 1751, 1752, 1755, 18268,
        18710, 18775, 18839, 18840, 19334, 19643, 1, 22088, 25349, 25499, 27502, 2, 40944, 4415, 4419, 4442, 4, 6218,
        623382, 64866, 65, 6, 751082, 7, 8,
    ]
    us_media_ids = sorted(us_media_ids)
    for media_id in us_media_ids:
        log.info("Adding media ID %d" % media_id)
        JobBroker(queue_name='MediaWords::Job::Sitemap::FetchMediaPages').add_to_queue(media_id=media_id)


if __name__ == "__main__":
    db_ = connect_to_db()
    # add_all_media_to_sitemap_queue(db=db_)
    add_us_media_to_sitemap_queue()
