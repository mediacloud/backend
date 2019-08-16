#!/usr/bin/env python3

import time

from mediawords.db import DatabaseHandler, connect_to_db
from mediawords.util.log import create_logger

log = create_logger(__name__)


def move_download_texts_rows_to_partitions(db: DatabaseHandler):
    """Gradually move download texts from "download_texts_np" to "download_texts_p"."""

    # How many download texts to move at the same time
    download_texts_chunk_size = 50 * 1000

    max_download_texts_id = db.query("SELECT MAX(download_texts_np_id) FROM download_texts_np").flat()[0]
    if max_download_texts_id is None:
        raise Exception("Max. download_texts_np_id ID is None.")

    log.info("Max. download texts ID: {}".format(max_download_texts_id))

    for start_download_texts_id in range(1, max_download_texts_id + 1, download_texts_chunk_size):
        end_download_texts_id = start_download_texts_id + download_texts_chunk_size - 1

        log.info("Moving rows with download_texts_id between {} and {} to the partitioned table...".format(
            start_download_texts_id,
            end_download_texts_id,
        ))

        moved_row_count = db.query(
            (
                'SELECT move_chunk_of_nonpartitioned_download_texts_to_partitions('
                '    %(start_download_texts_id)s, %(end_download_texts_id)s'
                ')'
            ),
            {'start_download_texts_id': start_download_texts_id, 'end_download_texts_id': end_download_texts_id}
        ).flat()[0]

        log.info("Moved {} rows with download_texts_id between {} AND {} to the partitioned table.".format(
            moved_row_count,
            start_download_texts_id,
            end_download_texts_id,
        ))

    log.info("All done!")

    # Weird, but otherwise Ansible deployments to mctest don't work due to this script exit(0)ing right away
    while True:
        time.sleep(1)


if __name__ == '__main__':
    db_ = connect_to_db()
    move_download_texts_rows_to_partitions(db_)
