#!/usr/bin/env python3

# FIXME untested after porting from Perl to Python

"""

Import feed downloads exported with "export_feed_downloads_from_backup_crawler.pl" back into database.

Usage: on production machine (database that is being imported to ), run:

    # Import feed downloads from "mediacloud-feed-downloads.csv"
    import_feed_downloads_to_db.pl mediacloud-feed-downloads.csv

"""
import csv
from http import HTTPStatus
import os
import sys
from typing import Dict, Union

from requests import Response as RequestsResponse

from mediawords.db import DatabaseHandler, connect_to_db
from mediawords.util.log import create_logger
from mediawords.util.web.user_agent import Response as UserAgentResponse

from crawler_fetcher.engine import handler_for_download

log = create_logger(__name__)


class FakeResponse(UserAgentResponse):
    """Fake response used to pretend that we've just downloaded something to be able to store it using a handler."""

    __slots__ = [
        '__content',
    ]

    def __init__(self, content: str):
        super().__init__(requests_response=RequestsResponse(), max_size=None)
        self.__content = content

    def code(self) -> int:
        return HTTPStatus.OK.value

    def message(self) -> str:
        return HTTPStatus.OK.description

    def headers(self) -> Dict[str, str]:
        return {}

    def header(self, name: str) -> Union[str, None]:
        return None

    def raw_data(self) -> bytes:
        return self.__content.encode('utf-8', errors='replace')

    def decoded_content(self) -> str:
        return self.__content


def import_feed_downloads(db: DatabaseHandler, csv_file: str) -> None:
    log.info(f"Importing downloads from {csv_file}...")

    db.begin()

    with open(csv_file, mode='r', encoding='utf-8') as f:

        # Guess dialect
        sample = f.read(1024)
        sniffer = csv.Sniffer()
        dialect = sniffer.sniff(sample)
        f.seek(0)

        input_csv = csv.DictReader(f, dialect=dialect)

        n = 1
        for download in input_csv:
            log.info(f"Importing download {n}...")
            n += 1

            raw_download_content = download.get('_raw_download_content', None)
            if raw_download_content:
                del raw_download_content['_raw_download_content']

                # Cast some columns
                download['feeds_id'] = int(download.get['feeds_id']) if 'feeds_id' in download else None  # NULL
                download['stories_id'] = int(download.get['stories_id']) if 'stories_id' in download else None  # NULL
                download['parent'] = int(download.get['parent']) if 'parent' in download else None  # NULL
                download['priority'] = int(download.get['priority']) if 'priority' in download else 0  # NOT NULL
                download['sequence'] = int(download.get['sequence']) if 'sequence' in download else 0  # NOT NULL
                download['sequence'] = 't' if download.get('extracted', False) else 'f'

                # Will be rewritten by handle_download()
                download['path'] = ''

                download = db.create(table='downloads', insert_hash=download)

                # Create mock response to import it
                response = FakeResponse(content=raw_download_content)
                handler = handler_for_download(db=db, download=download)
                handler.store_response(db=db, download=download, response=response)

    log.info("Committing...")
    db.commit()

    log.info(f"Done importing downloads from {csv_file}")


if __name__ == '__main__':

    usage_ex = Exception(f"Usage: {sys.argv[0]} file_to_import_from.csv")

    if len(sys.argv) != 2:
        raise usage_ex

    csv_file_ = sys.argv[1]
    if not os.path.isfile(csv_file_):
        raise usage_ex

    db_ = connect_to_db()
    import_feed_downloads(db=db_, csv_file=csv_file_)
