#!/usr/bin/env python3

"""
Migrate (install or update) database schema
"""

import argparse
import time

from mediawords.db import connect_to_db
from mediawords.util.log import create_logger
from migrate_schema import migration_sql

log = create_logger(__name__)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Migrate database schema.")
    parser.add_argument('-d', '--dry_run', action='store_true',
                        help="Print what is about to be executed instead of executing it")
    parser.add_argument('-s', '--sleep_after_finishing', action='store_true',
                        help="Sleep indefinitely after finishing the migration.")
    args = parser.parse_args()

    db_ = connect_to_db(require_schema=False)

    db_.begin()

    sql = migration_sql(db_)

    if sql:
        if args.dry_run:
            log.info("Printing migration SQL...")
            print(sql)
            log.info("Done printing migration SQL.")
        else:
            log.info("Executing migration SQL...")
            db_.query(sql)
            log.info("Done executing migration SQL.")

    else:
        log.info("Schema is up-to-date, nothing to do.")

    db_.commit()

    if args.sleep_after_finishing:
        while True:
            time.sleep(60)
