#!/usr/bin/env python3
#
# Purge PostgreSQL object caches
#

import time

from mediawords.db import connect_to_db
from mediawords.util.log import create_logger
from mediawords.util.process import run_alone

l = create_logger(__name__)


def purge_object_caches():
    """Call PostgreSQL function which purges PostgreSQL object caches."""

    # Wait for an hour between attempts to purge object caches
    delay_between_attempts = 60 * 60

    l.info("Starting to purge object caches...")
    while True:
        l.info("Purging object caches...")

        db = connect_to_db()
        db.query('SELECT cache.purge_object_caches()')
        db.disconnect()

        l.info("Purged object caches, sleeping for %d seconds." % delay_between_attempts)
        time.sleep(delay_between_attempts)


if __name__ == '__main__':
    run_alone(purge_object_caches)
