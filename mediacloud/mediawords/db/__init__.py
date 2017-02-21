from mediawords.db.handler import DatabaseHandler
from mediawords.test.db import using_test_database

from mediawords.util.config import get_config as py_get_config
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

l = create_logger(__name__)


class McConnectToDBException(Exception):
    """connect_to_db() exception."""
    pass


def connect_to_db(label: str = None, do_not_check_schema_version: bool = False) -> DatabaseHandler:
    """Connect to PostgreSQL."""

    label = decode_object_from_bytes_if_needed(label)

    # If this is Catalyst::Test run, force the label to the test database
    if using_test_database():
        label = 'test'

    config = py_get_config()

    if 'database' not in config:
        raise McConnectToDBException("No database connections are configured")

    all_settings = config['database']
    if all_settings is None:
        raise McConnectToDBException("No database connections are configured")

    settings = None
    if label is not None:
        for configured_database in all_settings:
            if configured_database['label'] == label:
                settings = configured_database
                break
        if settings is None:
            raise McConnectToDBException("No database connection settings labeled '%s'." % label)
    else:
        if len(all_settings) == 0:
            raise McConnectToDBException("No default connection settings found.")

        settings = all_settings[0]

    if settings is None:
        raise McConnectToDBException("Settings are undefined.")

    if 'host' not in settings or 'db' not in settings:
        raise McConnectToDBException("Settings are incomplete ('db' and 'host' must both be set).")

    host = settings['host']
    port = int(settings['port'])
    username = settings['user']
    password = settings['pass']
    database = settings['db']

    try:
        ret = DatabaseHandler(
            host=host,
            port=port,
            username=username,
            password=password,
            database=database,
            do_not_check_schema_version=do_not_check_schema_version
        )
    except Exception as ex:
        raise McConnectToDBException(
            "Unable to connect to database %(username)s@%(host)s:%(port)d/%(database)s: %(exception)s" % {
                'username': username,
                'host': host,
                'port': port,
                'database': database,
                'exception': str(ex)
            })

    if ret is None:
        raise McConnectToDBException("Error while connecting to the database.")

    if 'db_statement_timeout' in config['mediawords']:
        db_statement_timeout = config['mediawords']['db_statement_timeout']

        ret.query('SET statement_timeout TO %(db_statement_timeout)s' % {'db_statement_timeout': db_statement_timeout})

    # Reset the session variable in case the database connection is being reused due to pooling
    ret.query("""
        DO $$
        BEGIN
        PERFORM enable_story_triggers();
        EXCEPTION
        WHEN undefined_function THEN
            -- This exception will be raised if the database is uninitialized at this point.
            -- So, don't emit any kind of error because of an non-existent function.
            NULL;
        WHEN OTHERS THEN
            -- Forward the exception
            RAISE;
        END
        $$;
    """)

    return ret
