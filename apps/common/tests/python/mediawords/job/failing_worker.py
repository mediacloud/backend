#!/usr/bin/env python3

"""
Worker that fails right away.
"""

from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.process import fatal_error

log = create_logger(__name__)


def run_failing_worker() -> None:
    fatal_error(f"Failing worker.")


if __name__ == '__main__':
    app = JobBroker(queue_name='MediaWords::Job::FailingWorker')
    app.start_worker(handler=run_failing_worker)
