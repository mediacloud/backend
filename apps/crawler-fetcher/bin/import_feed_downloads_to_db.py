#!/usr/bin/env python3

# FIXME untested after porting from Perl to Python

# PLB: hacked 4/2022 to fetch download from S3
#       takes plain CSV of downloads table
"""

Import feed downloads exported with "export_feed_downloads_from_backup_crawler.pl" back into database.

Usage: on production machine (database that is being imported to ), run:

    # Import feeds using plain "psql --csv" dumps of tables
    import_feed_downloads_to_db.pl mediacloud-feed-downloads.csv

"""
import csv
from http import HTTPStatus
import os
import sys
from typing import Dict, Union

from requests import Response as RequestsResponse

from mediawords.db import DatabaseHandler, connect_to_db
from mediawords.dbi.downloads.store import fetch_content
from mediawords.util.log import create_logger
from mediawords.util.web.user_agent import Response as UserAgentResponse

from crawler_fetcher.engine import handler_for_download
from crawler_fatcher.fake_response import FakeResponse

SAVE_DOWNLOAD = False

log = create_logger(__name__)

def import_feed_downloads(db: DatabaseHandler, csv_file: str) -> None:
    log.info(f"Importing downloads from {csv_file}...")

    with open(csv_file, mode='r', encoding='utf-8') as f:
        try:
            # Guess dialect
            sample = f.read(1024)
            sniffer = csv.Sniffer()
            dialect = sniffer.sniff(sample)
        except:
            dialect = csv.unix_dialect

        f.seek(0)

        input_csv = csv.DictReader(f, dialect=dialect)
        skip_fields = list(input_csv.fieldnames) + ['reason', 'exception']

        # create unique .skipped file for each run
        n = 1
        while True:
            try:
                # eXclusive open: fails if exists
                sf = open(f"{csv_file}.skipped.{n}", 'x')
                skipped_csv = csv.DictWriter(sf, dialect=dialect, fieldnames=skip_fields)
                skipped_csv.writeheader()
                break
            except FileExistsError:
                n += 1
                continue

        def save_skipped(reason, exception=None):
            log.error(f"skipped {id}: {reason}")
            # XXX wait until now to create file??
            download['reason'] = reason
            download['exception'] = exception
            skipped_csv.writerow(download)
            sf.flush()
    
        n = 1
        for download in input_csv:
            id = download.get('downloads_id')
            log.info(f"Importing download {n} downloads_id {id}...")
            if not id:
                save_skipped("no downloads_id")
                continue

            n += 1

            # fetch original download from S3: MUST have downloads_id
            try:
                raw_download_content = fetch_content(db, download)
            except Exception as e:
                save_skippped("fetch_content", e)
                continue

            if raw_download_content == '(redundant feed)':
                save_skipped("redundant feed")
                continue
            elif not raw_download_content:
                save_skipped("empty download")
                continue

            log.info(f" raw_download_content len {len(raw_download_content)}")

            # PLB TEMP for tests, so I can see RSS contents
            if SAVE_DOWNLOAD:
                tmpfile = "tmp/download.{}".format(download['downloads_id'])
                with open(tmpfile, "w") as f:
                    f.write(raw_download_content)
                    log.debug(f"saved {tmpfile}")

            # Cast some columns
            download['feeds_id'] = int(download['feeds_id']) if 'feeds_id' in download else None  # NULL
            download['stories_id'] = int(download['stories_id']) if download.get('stories_id') else None  # NULL
            download['parent'] = int(download['parent']) if download.get('parent') else None  # NULL
            download['priority'] = int(download['priority']) if 'priority' in download else 0  # NOT NULL
            download['sequence'] = int(download['sequence']) if 'sequence' in download else 0  # NOT NULL
            # PLB: was sequence, again.
            download['extracted'] = 't' if download.get('extracted', False) else 'f'

            # PLB: off: autoindex not available if state = "success"?
            #download['path'] = ''
            #download['downloads_id'] = ''

            # allow do-overs.. maybe continue, without create??
            if db.find_by_id(table='downloads', object_id=id):
                save_skipped("exists")
                continue

            try:
                download = db.create(table='downloads', insert_hash=download)
            except Exception as e:
                save_skipped("create", e)
                continue

            try:
                # Create mock response to import it
                response = FakeResponse(content=raw_download_content)
                handler = handler_for_download(db=db, download=download)
                handler.S3_SAVE = False

                # DefaultStoreMixin.store_response calls
                #   AbstractDownloadFeedHandler.store_download which calls
                #     store_content (function)
                #     add_stories_from_feed (function) which calls
                #       parse_feed (function)

                db.begin()  # PLB pulled down
                handler.store_response(db=db, download=download, response=response)
                db.commit()
            except Exception as e:
                save_skipped("store", e)

    log.info(f"Done importing downloads from {csv_file}")


if __name__ == '__main__':

    usage_ex = Exception(f"Usage: {sys.argv[0]} file_to_import_from.csv")

    if len(sys.argv) != 2:
        raise usage_ex

    csv_file_ = sys.argv[1]
    if not os.path.isfile(csv_file_):
        raise usage_ex

    response = FakeResponse(content='')

    db_ = connect_to_db()
    import_feed_downloads(db=db_, csv_file=csv_file_)
