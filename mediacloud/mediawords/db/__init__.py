import typing

from mediawords.db.handler import DatabaseHandler
from mediawords.test.db.env import using_test_database

from mediawords.util.config import get_config as py_get_config
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_str_from_bytes_if_needed

log = create_logger(__name__)


class McConnectToDBException(Exception):
    """connect_to_db() exception."""
    pass


def connect_to_db(
        label: typing.Optional[str] = None,
        do_not_check_schema_version: bool = False,
        is_template: bool = False) -> DatabaseHandler:
    """Connect to PostgreSQL.

    Arguments:
    label - db config section label for mediawords.yml
    do_no_check_schema_version - if false, throw an error if the versions in mediawords.ym and the db do not match
    is_template - if true, connect to a db called <db_name>_template instead of <db_name>

    """
    label = decode_str_from_bytes_if_needed(label)

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

    if is_template:
        database = database + "_template"

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

    return ret
