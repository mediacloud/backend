#!/usr/bin/env python3
#
# Purge PostgreSQL object caches
#

import time

from mediawords.db import connect_to_db
from mediawords.util.log import create_logger

log = create_logger(__name__)


def purge_object_caches():
    """Call PostgreSQL function which purges PostgreSQL object caches."""

    # Wait for an hour between attempts to purge object caches
    delay_between_attempts = 60 * 60

    log.info("Starting to purge object caches...")
    while True:
        log.info("Purging object caches...")

        db = connect_to_db()
        db.query('SELECT cache.purge_object_caches()')
        db.disconnect()

        log.info("Purged object caches, sleeping for %d seconds." % delay_between_attempts)
        time.sleep(delay_between_attempts)


if __name__ == '__main__':
    purge_object_caches()
