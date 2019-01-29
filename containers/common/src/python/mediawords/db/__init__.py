from mediawords.db.handler import DatabaseHandler

from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_str_from_bytes_if_needed

log = create_logger(__name__)


class McConnectToDBException(Exception):
    """connect_to_db() exception."""
    pass


def connect_to_db(do_not_check_schema_version: bool = False) -> DatabaseHandler:
    """Connect to PostgreSQL.

    Arguments:
    label - db config section label for mediawords.yml
    do_no_check_schema_version - if false, throw an error if the versions in mediawords.ym and the db do not match
    """

    if isinstance(do_not_check_schema_version, bytes):
        do_not_check_schema_version = decode_str_from_bytes_if_needed(do_not_check_schema_version)
    do_not_check_schema_version = bool(int(do_not_check_schema_version))

    db_config = CommonConfig.database()

    try:
        ret = DatabaseHandler(
            host=db_config.hostname(),
            port=db_config.port(),
            username=db_config.username(),
            password=db_config.password(),
            database=db_config.database_name(),
            do_not_check_schema_version=do_not_check_schema_version
        )
    except Exception as ex:
        raise McConnectToDBException(
            "Unable to connect to database %(username)s@%(host)s:%(port)d/%(database)s: %(exception)s" % {
                'username': db_config.username(),
                'host': db_config.hostname(),
                'port': db_config.port(),
                'database': db_config.database_name(),
                'exception': str(ex)
            })

    if ret is None:
        raise McConnectToDBException("Error while connecting to the database.")

    return ret
