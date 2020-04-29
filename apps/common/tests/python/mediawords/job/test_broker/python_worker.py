#!/usr/bin/env python3

"""Test Python worker."""

from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


def run_job(x: int, y: int) -> int:
    if isinstance(x, bytes):
        x = decode_object_from_bytes_if_needed(x)

    if isinstance(y, bytes):
        y = decode_object_from_bytes_if_needed(y)

    x = int(x)
    y = int(y)

    log.info(f"Adding {x} and {y}...")

    return x + y


if __name__ == '__main__':
    app = JobBroker(queue_name='TestPythonWorker')
    app.start_worker(handler=run_job)
