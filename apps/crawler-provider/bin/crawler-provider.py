#!/usr/bin/env python3

from mediawords.db import connect_to_db
from crawler_provider import run_provider


if __name__ == '__main__':
    db = connect_to_db()
    run_provider(db)
