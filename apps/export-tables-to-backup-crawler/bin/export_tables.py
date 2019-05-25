#!/usr/bin/env python3
#
# Export "media", "feeds", ... table data needed to run a backup crawler
#
# Usage:
#
# 1) On production machine (database that is being exported), run:
#
#     # Export table data to "mediacloud-dump.sql"
#     ./tools/export_import/export_tables_to_backup_crawler.py > mediacloud-dump.sql
#
# 2) On target machine (e.g. a backup crawler), run:
#
#     # Create database
#     createdb mediacloud
#
#     # Import empty schema
#     psql -f script/mediawords.sql mediacloud
#
#     # Import tables from "mediacloud-dump.sql"
#     psql -v ON_ERROR_STOP=1 -f mediacloud-dump.sql mediacloud
#

from mediawords.db import connect_to_db
from export_tables_to_backup_crawler.export_tables import print_exported_tables_to_backup_crawler

if __name__ == '__main__':
    db = connect_to_db()
    print_exported_tables_to_backup_crawler(db=db)
