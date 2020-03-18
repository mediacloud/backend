#!/usr/bin/env python3

"""Topic Mapper job that generates timespan_maps for a timespans or all timespans in a snapshot."""

import time
from typing import Optional

from mediawords.db import connect_to_db
from mediawords.job import JobBroker
from topics_map.map import generate_and_store_maps
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

QUEUE_NAME = 'MediaWords::Job::TM::Map'

class McTopicMapJobException(Exception):
    """Exceptions dealing with job setup and routing."""
    pass


def run_job(snapshots_id: int=None, timespans_id: int=None) -> None:
    """Generate and store network maps for either a single timespan or all timespans in a snapshot."""
    global _consecutive_requeues

    if isinstance(snapshots_id, bytes):
        snapshots_id = decode_object_from_bytes_if_needed(snapshots_id)
    if snapshots_id is not None:
        snapshots_id = int(snapshots_id)

    if isinstance(timespans_id, bytes):
        timespans_id = decode_object_from_bytes_if_needed(timespans_id)
    if timespans_id is not None:
        timespans_id = int(timespans_id)

    if (snapshots_id and timespans_id) or (not snapshots_id and not timespans_id):
        raise McTopicMapJobException("exactly one of snapshots_id or timespans_id must be set.")

    db = connect_to_db()

    if snapshots_id:
        timespans_ids = db.query(
            "select timespans_id from timespans where snapshots_id = %(a)s",
            {'a': snapshots_id}
        ).flat()
    else:
        timespans_ids = (timespans_id,)

    for timespans_id in timespans_ids:
        log.info("generating maps for timespan %s" % timespans_id)
        generate_and_store_maps(db, timespans_id)


if __name__ == '__main__':
    app = JobBroker(queue_name=QUEUE_NAME)
    app.start_worker(handler=run_job)
