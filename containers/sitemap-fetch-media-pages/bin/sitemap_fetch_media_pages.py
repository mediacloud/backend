#!/usr/bin/env python3

from mediawords.db import connect_to_db
from mediawords.job import AbstractJob, JobBrokerApp
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed
from mediawords.util.sitemap.media import fetch_sitemap_pages_for_media_id

log = create_logger(__name__)


class FetchMediaPages(AbstractJob):
    """Fetch all media's pages (news stories and not) from XML sitemap."""

    @classmethod
    def run_job(cls, media_id: int) -> None:
        if isinstance(media_id, bytes):
            media_id = decode_object_from_bytes_if_needed(media_id)

        media_id = int(media_id)

        db = connect_to_db()

        fetch_sitemap_pages_for_media_id(db=db, media_id=media_id)

    @classmethod
    def queue_name(cls) -> str:
        return 'MediaWords::Job::Sitemap::FetchMediaPages'


if __name__ == '__main__':
    app = JobBrokerApp(queue_name=FetchMediaPages.queue_name())
    app.start_worker()
