#!/usr/bin/env python3

# PLB 4/2022: from import_feed_downloads_to_db.py
"""
Import feeds using plain "psql --csv" dumps of downloads table
where download data is present in Amazon S3.

Usage: on production machine (database that is being imported to ), run:

    queue_feed_downloads.py mediacloud-feed-downloads.csv QueueName

       Reads PLAIN CSV of downloads table (just the native columns).
       Inserts row into downloads table
       Queues downloads_id to work queue for a feed_parse_worker.py pool.

       ASSUMES: path column points to valid S3 download.

"""
import csv
import os
import sys

from mediawords.db import DatabaseHandler, connect_to_db
from mediawords.util.log import create_logger

from crawler_fetcher.queue import queue_to_feed_parse_worker

log = create_logger(__name__)

def queue_feed_downloads(db: DatabaseHandler, csv_file: str, queue: str, time_prefix: str = '') -> None:
    log.info(f"Queueing downloads from {csv_file} to {queue}...")

    with open(csv_file, mode='r', encoding='utf-8') as f:
        try:
            # Guess dialect
            sample = f.read(1024)
            sniffer = csv.Sniffer()
            dialect = sniffer.sniff(sample)
        except:
            # here with output from "psql --csv"
            dialect = csv.unix_dialect

        f.seek(0)

        input_csv = csv.DictReader(f, dialect=dialect)

        for download in input_csv:
            download_time = download.get('download_time')
            if time_prefix and not download_time.startswith(time_prefix):
                # XXX break loop if download_time > time_prefix??
                continue

            def skipped(reason, exc=None):
                # XXX save to file?
                log.error(f"{reason}: {download}")
                if exc:
                    log.error(exc)

            try:
                id = int(download['downloads_id'])
            except Exception as e:
                skipped("downloads_id", e)
                continue

            # Cast some columns
            download['feeds_id'] = int(download['feeds_id']) if 'feeds_id' in download else None  # NULL
            download['stories_id'] = int(download['stories_id']) if download.get('stories_id') else None  # NULL
            download['parent'] = int(download['parent']) if download.get('parent') else None  # NULL
            download['priority'] = int(download['priority']) if 'priority' in download else 0  # NOT NULL
            download['sequence'] = int(download['sequence']) if 'sequence' in download else 0  # NOT NULL
            # PLB: was sequence, again.
            download['extracted'] = 't' if download.get('extracted', False) else 'f'

            # PLB: off: autoindex not available if state = "success", so keeping downloads_id and path.

            # Not sure; maybe continue??
            if db.find_by_id(table='downloads', object_id=id):
                skipped("exists")
                continue

            # XXX PLB log current time (typ. not run as top process in container)?
            log.info(f"Importing downloads_id {id} download_time {download_time}...")

            db.begin()
            try:
                download = db.create(table='downloads', insert_hash=download)
            except Exception as e:
                # here with 4n key constraints...
                db.rollback()
                skipped("create", e)
                continue

            try:
                queue_to_feed_parse_worker(queue, id)
            except Exception as e:
                db.rollback()
                skipped("queue", e)
            db.commit()

    log.info(f"Done queuing downloads from {csv_file}")

if __name__ == '__main__':
    def usage():
        sys.stderr.write(f"Usage: {sys.argv[0]} [--create-queue] file_to_import_from.csv queue [time_prefix]\n")
        os.exit(1)

    argc = len(sys.argv)
    if len(sys.argv) < 2:
        usage()

    # XXX PLB should use real arg parser...
    optind = 1

# would like to be able to pass task_create_missinq_queues to Celery()
#    create_queue = False
#    while optind < argc and sys.argv[optind][0] == '-':
#        if sys.argv[optind] == '--create-queue':
#            create_queue = True
#        else:
#            usage()
#        optind += 1

    if optind == argc:
        usage()
    csv_file_ = sys.argv[optind]
    if not os.path.isfile(csv_file_):
        usage()
    optind += 1

    if optind == argc:
        usage()
    queue = sys.argv[optind]
    optind += 1

    if optind == argc:
        time_prefix = ''
    else:
        time_prefix = sys.argv[optind]
        optind += 1

    if optind != argc:
        usage()

    db_ = connect_to_db()
    queue_feed_downloads(db_, csv_file_, queue, time_prefix)
