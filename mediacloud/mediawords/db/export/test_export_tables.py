from io import StringIO
import tempfile

from mediawords.db import connect_to_db
from mediawords.db.export.export_tables import *
from mediawords.util.paths import mc_sql_schema_path
from mediawords.util.process import run_command_in_foreground
from mediawords.util.text import random_string


def test_print_exported_tables_to_backup_crawler():
    # Basic sanity test to make sure something gets printed out to STDOUT and that it can be imported back with `psql`
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

    # Try importing with psql (because this is how it's going to be imported)
    temp_database_name = 'mediacloud_test_%s' % random_string(length=16)

    run_command_in_foreground(['createdb', temp_database_name])

    temp = tempfile.NamedTemporaryFile()
    temp.write(bytes(sql_dump, 'UTF-8'))
    temp.flush()
    temp_sql_dump_path = temp.name

    mediawords_sql_path = mc_sql_schema_path()

    run_command_in_foreground(['psql', '-v', 'ON_ERROR_STOP=1', '-f', mediawords_sql_path, '-d', temp_database_name])
    run_command_in_foreground(['psql', '-v', 'ON_ERROR_STOP=1', '-f', temp_sql_dump_path, '-d', temp_database_name])

    run_command_in_foreground(['dropdb', temp_database_name])
