#!/usr/bin/env python3

import time

from mediawords.db import connect_to_db
from mediawords.util.log import create_logger
from mediawords.util.process import run_alone

log = create_logger(__name__)


def move_nonpartitioned_downloads_to_partitions():
    """Gradually move downloads from "downloads_np" to "downloads_p"."""

    # How many downloads to move at the same time
    downloads_chunk_size = 50 * 1000

    db = connect_to_db()

    max_downloads_id = db.query("SELECT MAX(downloads_np_id) FROM downloads_np").flat()[0]
    if max_downloads_id is None:
        raise Exception("Max. downloads_id ID is None.")

    log.info("Max. download ID: {}".format(max_downloads_id))

    for start_downloads_id in range(43850001, max_downloads_id + 1, downloads_chunk_size):
        end_downloads_id = start_downloads_id + downloads_chunk_size - 1

        log.info("Moving rows with downloads_id between {} and {} to the partitioned table...".format(
            start_downloads_id,
            end_downloads_id,
        ))

        moved_row_count = db.query(
            'SELECT move_chunk_of_nonpartitioned_downloads_to_partitions(%(start_downloads_id)s, %(end_downloads_id)s)',
            {'start_downloads_id': start_downloads_id, 'end_downloads_id': end_downloads_id}
        ).flat()[0]

        log.info("Moved {} rows with downloads_id between {} AND {} to the partitioned table.".format(
            moved_row_count,
            start_downloads_id,
            end_downloads_id,
        ))

    log.info("All done!")

    # Weird, but otherwise Ansible deployments to mctest don't work due to this script exit(0)ing right away
    while True:
        time.sleep(1)


if __name__ == '__main__':
    run_alone(move_nonpartitioned_downloads_to_partitions)
