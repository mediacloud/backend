#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sitemap.media import fetch_sitemap_pages_for_media_id

log = create_logger(__name__)


def run_sitemap_fetch_media_pages(media_id: int) -> None:
    """Fetch all media's pages (news stories and not) from XML sitemap."""
    if isinstance(media_id, bytes):
        media_id = decode_object_from_bytes_if_needed(media_id)

    media_id = int(media_id)

    db = connect_to_db()

    fetch_sitemap_pages_for_media_id(db=db, media_id=media_id)


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::Sitemap::FetchMediaPages')
    app.start_worker(handler=run_sitemap_fetch_media_pages)
