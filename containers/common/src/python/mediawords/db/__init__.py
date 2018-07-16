import typing

from mediawords.db.handler import DatabaseHandler
from mediawords.test.db.env import using_test_database

import mediawords.util.config
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

    host = mediawords.util.config.postgresql_hostname()
    port = mediawords.util.config.postgresql_port()
    username = mediawords.util.config.postgresql_username()
    password = mediawords.util.config.postgresql_password()
    database = mediawords.util.config.postgresql_database()

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

    db_statement_timeout = mediawords.util.config.db_statement_timeout()
    if db_statement_timeout:
        ret.query('SET statement_timeout TO %(db_statement_timeout)s' % {'db_statement_timeout': db_statement_timeout})

    return ret
