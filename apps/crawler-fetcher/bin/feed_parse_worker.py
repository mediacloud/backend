#!/usr/bin/env python3
"""
PLB 4/11/22 from extract_and_vector_worker.py and import_feed_downloads_to_db.py
        process feeds queued by queue_feed_downloads.py
        (and possibly future crawler-fetcher)

        MUST be passed work queue name in MC_FEED_PARSE_QUEUE env var
        to allow different queues/worker pools for different inputs.
"""

import time

from mediawords.db import DatabaseHandler, connect_to_db
from mediawords.dbi.downloads.store import fetch_content
from mediawords.job import JobBroker
from mediawords.util.log import create_logger

from crawler_fetcher.engine import handler_for_download
from crawler_fetcher.fake_response import FakeResponse

log = create_logger(__name__)

MC_FEED_PARSE_QUEUE = 'MC_FEED_PARSE_QUEUE'
"""Variable name to hold environment variable name!"""

# remnant from extract_and_vector.
# mostly letting actual errors fly, for better tracebacks?
class McFeedParseWorkerException(Exception):
    """ExtractAndVectorJob exception."""
    pass


# PLB: extract_and_vector has other stuff, seeing if it matters
# arguments passed by crawler_fetcher.queue.queue_to_feed_parse_worker
def _feed_parse_worker(db: DatabaseHandler, downloads_id: int) -> bool:
    """Process a feed download from S3."""

    downloads_id = int(downloads_id)

    if not downloads_id:
        raise McFeedParseWorkerException("'downloads_id' is not set.")

    # PLB: code from import_feed_downloads_to_db.py
    download = db.find_by_id(table='downloads', object_id=downloads_id)
    if not download:
        log.warn(f"Download {downloads_id} not found")
        return False

    # XXX maybe check downloads.extracted???

    log.info(f"Fetching download {downloads_id} download_time {download.get('download_time')}")
    # fetch original download from S3: MUST have downloads_id
    raw_download_content = fetch_content(db, download)

    if raw_download_content == '(redundant feed)':
        log.info(f"{downloads_id}: redundant feed")
        return True         # no error

    if not raw_download_content:
        log.warn(f"{downloads_id}: raw_download_content empty")
        return False

    log.debug(f"{downloads_id}: raw_download_content len {len(raw_download_content)}")

    log.info(f"Parsing download {downloads_id}...")

    # Currently need mock response to parse it...
    response = FakeResponse(content=raw_download_content)
    handler = handler_for_download(db=db, download=download)

    # create all stories in a single transaction
    db.begin()

    # NOTE! store=False; download is already on S3, so
    # skip store_content and just run add_stories_from_feed.
    # Maybe should have separate {store,parse}_download methods?
    handler.store_response(db=db, download=download, response=response, store=False)

    # XXX maybe update downloads.extracted = 't'??
    # (BUT that's slow with a citus sharded table)
    db.commit()

    log.info(f"Done parsing download {downloads_id}.")
    return True

def feed_parse_worker(downloads_id: int):
    """Process a feed download from S3."""

    db = connect_to_db()
    _feed_parse_worker(db, downloads_id)
    db.disconnect()

if __name__ == '__main__':
    import os

    # require queue name; can have different queues/worker pools
    #   for current and historical data.  There is not (currently)
    #   a default queue name, if there is, declare it in
    #   crawler_fetacher/queue.py??
    queue_name = os.environ.get(MC_FEED_PARSE_QUEUE)
    if not queue_name:
        log.error(f"Must have queue name in {MC_FEED_PARSE_QUEUE}")

    # NOTE!! Always creates queue!!
    app = JobBroker(queue_name=queue_name)
    app.start_worker(handler=feed_parse_worker)
