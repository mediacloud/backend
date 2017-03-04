from io import StringIO

from mediawords.db import connect_to_db
from mediawords.db.export.export_tables import *


def test_export_tables_to_backup_crawler():
    # Basic sanity test to make sure something gets printed out to STDOUT
    # FIXME it would be better to try importing the resulting dump somewhere
    db = connect_to_db()

    orig_stdout = sys.stdout
    sys.stdout = captured_stdout = StringIO()

    export_dump_exception = None
    try:
        export_tables_to_backup_crawler(db=db)
    except Exception as ex:
        export_dump_exception = str(ex)

    sys.stdout = orig_stdout

    assert export_dump_exception is None

    sql_dump = captured_stdout.getvalue()
    assert 'COPY media' in sql_dump
