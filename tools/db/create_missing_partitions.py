#!/usr/bin/env python3
#
# Create missing partitions for for partitioned tables
#

import time

from mediawords.db import connect_to_db
from mediawords.util.log import create_logger
from mediawords.util.process import run_alone

l = create_logger(__name__)


def create_missing_partitions():
    """Call PostgreSQL function which creates missing table partitions (if any)."""

    # Wait for an hour between attempts to create new partitions
    delay_between_attempts = 60 * 60

    l.info("Starting to create missing partitions...")
    while True:
        l.info("Creating missing partitions...")

        db = connect_to_db()
        db.query('SELECT create_missing_partitions()')
        db.disconnect()

        l.info("Created missing partitions, sleeping for %d seconds." % delay_between_attempts)
        time.sleep(delay_between_attempts)


if __name__ == '__main__':
    run_alone(create_missing_partitions)
