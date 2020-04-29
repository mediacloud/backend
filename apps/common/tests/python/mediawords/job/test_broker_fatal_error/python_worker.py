#!/usr/bin/env python3

"""
Worker that fails pretty much right away.
"""

import subprocess
import time

from mediawords.job import JobBroker
from mediawords.util.log import create_logger
from mediawords.util.process import fatal_error

log = create_logger(__name__)


def run_job() -> None:
    # Start some background processes to see if they get killed properly
    # noinspection PyUnusedLocal
    bg_process_1 = subprocess.Popen(["sleep", "30"])
    # noinspection PyUnusedLocal
    bg_process_2 = subprocess.Popen(["sleep", "30"])

    # Wait for the children processes to fire up
    time.sleep(1)

    fatal_error(f"Failing worker.")


if __name__ == '__main__':
    app = JobBroker(queue_name='TestPythonWorkerFatalError')
    app.start_worker(handler=run_job)
