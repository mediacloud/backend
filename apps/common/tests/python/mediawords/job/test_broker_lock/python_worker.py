#!/usr/bin/env python3

"""Test Python worker with a lock."""

import time

from mediawords.job import JobBroker, JobLock
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


# noinspection DuplicatedCode
def run_job(test_id: int, x: int, y: int) -> int:
    if isinstance(test_id, bytes):
        test_id = decode_object_from_bytes_if_needed(test_id)

    if isinstance(x, bytes):
        x = decode_object_from_bytes_if_needed(x)

    if isinstance(y, bytes):
        y = decode_object_from_bytes_if_needed(y)

    test_id = int(test_id)
    x = int(x)
    y = int(y)

    log.info(f"Test ID {test_id}: adding {x} and {y}...")

    # In this time we should be able to add another job and make sure that it gets locked out from running
    time.sleep(10)

    return x + y


if __name__ == '__main__':
    app = JobBroker(queue_name='TestPythonWorkerLock')
    app.start_worker(
        handler=run_job,
        lock=JobLock(
            lock_type='TestPythonWorkerLock',
            lock_arg='test_id',
        ),
    )
