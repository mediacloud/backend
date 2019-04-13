from io import StringIO
import sys

from mediawords.db import connect_to_db
from mediawords.db.export.export_tables import print_exported_tables_to_backup_crawler


def test_print_exported_tables_to_backup_crawler():
    # Basic sanity test to make sure something gets printed out to STDOUT
    # FIXME try importing the dump into a test database
    db = connect_to_db()

    orig_stdout = sys.stdout
    sys.stdout = captured_stdout = StringIO()

    export_dump_exception = None
    try:
        print_exported_tables_to_backup_crawler(db=db)
    except Exception as ex:
        export_dump_exception = str(ex)

    sys.stdout = orig_stdout

    assert export_dump_exception is None

    sql_dump = captured_stdout.getvalue()
    assert 'COPY media' in sql_dump
