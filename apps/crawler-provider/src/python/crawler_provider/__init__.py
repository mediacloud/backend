"""
mediawords.crawler.provider - add downloads to the queued_downloads table for processing by crawler_fetcher jobs

The provider is responsible for adding downloads to the crawler_fetcher jobs queue.  The basic job
of the provider is just to query the downloads table for any downloads with "state = 'pending'".
Most 'pending' downloads are added by the crawler fetcher/handler when the url for a new story is discovered
in a just downloaded feed.

But the provider is also responsible for periodically adding feed downloads to the queue.  The provider uses a back off
algorithm that starts by downloading a feed five minutes after a new story was last found and then doubles the delay
each time the feed is download and no new story is found, until the feed is downloaded only once a week.

The provider is also responsible for throttling downloads by host, so a download from each host is only provided
once per second.

The provider works as a daemon, periodically checking the size queued_downloads and only adding
new jobs to the queue if there are more than MAX_QUEUE_SIZE jobs in the table.  This allows us to implement
throttling by keeping the crawler jobs queue relatively small, thus limiting the number of requests for each
host over a period of several minutes, while allowing the crawler_fetcher jobs to acts as simple stupid
worker jobs that just do a quick query of queued_downloads to grab the oldest queued download.
"""

import time
from typing import List, Any, Iterator

from mediawords.db import DatabaseHandler
from mediawords.util.log import create_logger

log = create_logger(__name__)

# how often to download each feed (seconds)
STALE_FEED_INTERVAL = 60 * 60 * 24 * 7

# how often to check for feeds to download (seconds)
STALE_FEED_CHECK_INTERVAL = 60 * 30

# timeout for download in fetching state (seconds)
STALE_DOWNLOAD_INTERVAL = 60 * 60 * 24

# do not add downloads to queued_downloads if there are already this many rows in the table
MAX_QUEUE_SIZE = 10 * 1000

# sleep this many seconds between each queue attempt
QUEUE_INTERVAL = 1

# truncate table queued_downloads after this many seconds to avoid dead row bloat in the table
QUEUE_TRUNCATE_INTERVAL = 3600


def _timeout_stale_downloads(db: DatabaseHandler) -> None:
    """Move fetching downloads back to pending after STALE_DOWNLOAD_INTERVAL.

    This shouldn't technically happen, but we want to make sure that
    no hosts get hung b/c a download sits around in the fetching state forever
    """
    vars(_timeout_stale_downloads).setdefault('last_check', 0)
    if _timeout_stale_downloads.last_check > time.time() - STALE_DOWNLOAD_INTERVAL:
        return

    _timeout_stale_downloads.last_check = time.time()

    db.query(
        """
        UPDATE downloads SET
            state = 'pending',
            download_time = NOW()
        WHERE state = 'fetching'
          AND download_time < now() - (%(a)s || ' seconds')::interval
        """,
        {'a': STALE_DOWNLOAD_INTERVAL})


def _add_stale_feeds(db: DatabaseHandler) -> None:
    """Add pending downloads for all stale feeds."""
    vars(_add_stale_feeds).setdefault('last_check', 0)
    if _add_stale_feeds.last_check > time.time() - STALE_FEED_CHECK_INTERVAL:
        return

    _add_stale_feeds.last_check = time.time()

    # If the table doesn't exist, PostgreSQL sends a NOTICE which breaks the "no warnings" unit test
    db.query('SET client_min_messages=WARNING')
    db.query('DROP TABLE IF EXISTS feeds_to_queue')
    db.query('SET client_min_messages=NOTICE')

    db.query(
        """
        CREATE TEMPORARY TABLE feeds_to_queue AS
        SELECT feeds_id,
               url
        FROM feeds
        WHERE active = 't'
          AND url ~ 'https?://'
          AND (
            -- Never attempted
            last_attempted_download_time IS NULL

            -- Feed was downloaded more than stale_feed_interval seconds ago
            OR (last_attempted_download_time < (NOW() - (%(a)s || ' seconds')::interval))

            -- (Probably) if a new story comes in every "n" seconds, re-fetch feed every "n" + 5 minutes
            OR (
                (NOW() > last_attempted_download_time +
                        (last_attempted_download_time - last_new_story_time) + interval '5 minutes')

                -- "web_page" feeds are to be downloaded only once a week,
                -- independently from when the last new story comes in from the
                -- feed (because every "web_page" feed download provides a
                -- single story)
                AND type != 'web_page'
            )
          )
        """,
        {'a': STALE_FEED_INTERVAL})

    db.query(
        """
        -- noinspection SqlResolve @ table/"feeds_to_queue"
        UPDATE feeds
        SET last_attempted_download_time = NOW()
        WHERE feeds_id IN (SELECT feeds_id FROM feeds_to_queue)
        """)

    # noinspection SqlResolve,SqlCheckUsingColumns
    downloads = db.query(
        """
        WITH inserted_downloads as (
            INSERT INTO downloads (feeds_id, url, host, type, sequence, state, priority, download_time, extracted)
            SELECT feeds_id,
                   url,
                   LOWER(SUBSTRING(url from '.*://([^/]*)' )),
                   'feed',
                   1,
                   'pending',
                   0,
                   NOW(),
                   false
            FROM feeds_to_queue
            RETURNING *
        )

        select d.*, f.media_id as _media_id
            from inserted_downloads d
                join feeds f using (feeds_id)
        """).hashes()

    db.query("""
        -- noinspection SqlResolveForFile
        drop table feeds_to_queue
    """)

    log.info(f"Added stale feeds: {len(downloads)}")


def provide_download_ids(db: DatabaseHandler) -> List[int]:
    """Return a list of pending downloads ids to queue for fetching.

    Hand out one downloads_id for each distinct host with a pending download.

    Every STALE_FEED_INTERVAL, add downloads for all feeds that are due to be downloaded again according to
    the back off algorithm.
    """
    _timeout_stale_downloads(db)

    _add_stale_feeds(db)

    log.info("Querying pending downloads...")

    # get one downloads_id per host, ordered by priority asc, downloads_id desc
    # noinspection SqlResolve
    downloads_ids = db.query("""

        -- Pending downloads by host, ranked by priority and the biggest "downloads_id"  
        WITH pending_downloads_per_host AS (
    
            SELECT
                host,
                downloads_id,
                ROW_NUMBER() OVER(
                    PARTITION BY host
                    ORDER BY
                        priority,
                        downloads_id DESC NULLS LAST
                ) AS rank
            FROM downloads_pending AS dp
            WHERE (
                SELECT 1
                FROM queued_downloads AS qd
                WHERE qd.downloads_id = dp.downloads_id
            ) IS NULL
        )
        
        SELECT downloads_id
        FROM pending_downloads_per_host
        WHERE rank = 1
    
    """).flat()

    log.info(f"Providing {len(downloads_ids)} per-host download IDs")

    return downloads_ids


def __chunks(list_to_be_chunked: List[Any], chunk_size: int) -> Iterator[List[Any]]:
    """Yield successive chunks from parameter list."""
    for i in range(0, len(list_to_be_chunked), chunk_size):
        yield list_to_be_chunked[i:i + chunk_size]


def run_provider(db: DatabaseHandler, daemon: bool = True) -> None:
    """Run the provider daemon to periodically add crawler_fetcher jobs by querying for pending downloads.

    Poll forever as a daemon.  Every QUEUE_INTERVAL seconds, check whether queued_downloads
    has less than MAX_QUEUE_SIZE jobs. If it does, call provide_download_ids and queue a
    fetcher job for each provided download_id.

    When run as a daemon, this function effectively throttles each host to no more than one download every
    QUEUE_INTERVAL seconds because provide_download_ids only provides one downloads_id for each host.
    """
    last_queue_time = 0
    last_queue_truncate_time = time.time()
    while True:
        if time.time() - last_queue_truncate_time > QUEUE_TRUNCATE_INTERVAL:
            db.query("truncate table queued_downloads")
            last_queue_truncate_time = time.time()

        queue_size = db.query(
            "select count(*) from ( select 1 from queued_downloads limit %(a)s ) q",
            {'a': MAX_QUEUE_SIZE * 10}).flat()[0]
        log.info(f"Queue size: {queue_size}")

        if queue_size < MAX_QUEUE_SIZE:
            downloads_ids = provide_download_ids(db)

            if downloads_ids:
                log.info(f"Adding {len(downloads_ids)} download IDs to queue...")

                # Insert in chunks so that:
                # 1) Fetchers get to fetching sooner;
                # 2) We don't have to come up with a query that's 2 MB long.
                for chunk_downloads_ids in __chunks(list_to_be_chunked=downloads_ids, chunk_size=1000):
                    log.info(f"Inserting chunk of downloads ({len(chunk_downloads_ids)} download IDs)...")
                    # noinspection SqlResolve,SqlSignature
                    db.query(
                        """
                        INSERT INTO queued_downloads (downloads_id)
                        VALUES (unnest (ARRAY %(chunk_downloads_ids)s::bigint[]))
                        ON CONFLICT (downloads_id) DO NOTHING
                        """ % {
                            'chunk_downloads_ids': chunk_downloads_ids,
                        }
                    )

            else:
                log.info("No download IDs to add")

            if daemon:
                if time.time() - last_queue_time < QUEUE_INTERVAL:
                    log.info(f"Sleeping for {QUEUE_INTERVAL} seconds")
                    time.sleep(QUEUE_INTERVAL)

        elif daemon:
            time_to_sleep = QUEUE_INTERVAL * 10
            log.info(f"Sleeping for {time_to_sleep} seconds as we're running as a daemon")
            time.sleep(time_to_sleep)

        last_queue_time = time.time()

        if not daemon:
            break
