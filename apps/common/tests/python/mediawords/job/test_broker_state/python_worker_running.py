#!/usr/bin/env python3

"""Test stateful Python worker which runs forever."""

import time
from typing import Optional

from mediawords.job import StatefulJobBroker, JobState, StateUpdater
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


# noinspection DuplicatedCode,PyUnusedLocal
def run_job(test_job_states_id: int, x: int, y: int, state_updater: Optional[StateUpdater] = None):
    if isinstance(test_job_states_id, bytes):
        test_job_states_id = decode_object_from_bytes_if_needed(test_job_states_id)
    if isinstance(x, bytes):
        x = decode_object_from_bytes_if_needed(x)
    if isinstance(y, bytes):
        y = decode_object_from_bytes_if_needed(y)

    x = int(x)
    y = int(y)

    log.info(f"Starting 'running' Python worker (test job state ID: {test_job_states_id})...")

    # Sleep indefinitely to keep the job in "running" state
    while True:
        time.sleep(10)


if __name__ == '__main__':
    app = StatefulJobBroker(queue_name='TestPythonWorkerStateRunning')
    app.start_worker(
        handler=run_job,
        state=JobState(
            table='test_job_states',
            state_column='state',
            message_column='message',
        ),
    )
