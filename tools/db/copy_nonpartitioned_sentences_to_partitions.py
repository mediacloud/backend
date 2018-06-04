#!/usr/bin/env python3

import time

from mediawords.db import connect_to_db
from mediawords.util.log import create_logger
from mediawords.util.process import run_alone

log = create_logger(__name__)


def copy_nonpartitioned_sentences_to_partitions():
    """Gradually copy sentences from "story_sentences_nonpartitioned" to "story_sentences_partitioned"."""

    # How many stories the sentences of which to copy at the same time
    stories_chunk_size = 50 * 1000

    db = connect_to_db()

    # With 512 MB, database can deduplicate (sort) sentences in memory instead of disk
    db.query("SET work_mem TO '512MB'")

    max_stories_id = db.query("SELECT MAX(stories_id) FROM stories").flat()[0]
    if max_stories_id is None:
        raise Exception("Max. stories ID is None.")

    log.info("Max. stories ID: {}".format(max_stories_id))

    for start_stories_id in range(234200000, max_stories_id + 1, stories_chunk_size):
        end_stories_id = start_stories_id + stories_chunk_size - 1

        log.info("Copying sentences of stories_id BETWEEN {} AND {} to the partitioned table...".format(
            start_stories_id,
            end_stories_id,
        ))

        copied_sentences = db.query(
            'SELECT copy_chunk_of_nonpartitioned_sentences_to_partitions(%(start_stories_id)s, %(end_stories_id)s)',
            {'start_stories_id': start_stories_id, 'end_stories_id': end_stories_id}
        ).flat()[0]

        log.info("Copied {} sentences of stories_id BETWEEN {} AND {} to the partitioned table.".format(
            copied_sentences,
            start_stories_id,
            end_stories_id,
        ))

    log.info("All done!")

    # Weird, but otherwise Ansible deployments to mctest don't work due to this script exit(0)ing right away
    while True:
        time.sleep(1)


if __name__ == '__main__':
    run_alone(copy_nonpartitioned_sentences_to_partitions)
