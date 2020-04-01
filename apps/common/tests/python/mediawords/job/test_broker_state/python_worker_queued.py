#!/usr/bin/env python3

"""Test stateful Python worker which doesn't even run."""

import time

from mediawords.util.log import create_logger

log = create_logger(__name__)

if __name__ == '__main__':
    log.info(f"Starting 'queued' Python worker...")

    # Sleep indefinitely to keep the job in "queued" state
    while True:
        time.sleep(10)
