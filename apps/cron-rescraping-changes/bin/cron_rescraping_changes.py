#!/usr/bin/env python3

import time

from mediawords.db import connect_to_db
from mediawords.db.handler import DatabaseHandler
from mediawords.util.log import create_logger

log = create_logger(__name__)


def print_rescraping_changes(db: DatabaseHandler):
    """Print rescraping changes."""

    db.query("SELECT rescraping_changes()")

    db.query("SELECT update_feeds_from_yesterday()")


if __name__ == '__main__':
    db = connect_to_db()
    print_rescraping_changes(db)
