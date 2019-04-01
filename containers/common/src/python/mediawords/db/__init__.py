from mediawords.db.handler import DatabaseHandler

from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger

log = create_logger(__name__)


class McConnectToDBException(Exception):
    """connect_to_db() exception."""
    pass


def connect_to_db() -> DatabaseHandler:
    """Connect to PostgreSQL."""

    db_config = CommonConfig.database()

    try:
        ret = DatabaseHandler(
            host=db_config.hostname(),
            port=db_config.port(),
            username=db_config.username(),
            password=db_config.password(),
            database=db_config.database_name(),
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
