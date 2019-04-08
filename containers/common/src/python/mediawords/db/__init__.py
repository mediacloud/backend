import time

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
    retries_config = db_config.retries()

    assert retries_config.max_attempts() > 0, "max_tries can't be negative."

    db = None

    for attempt in range(1, retries_config.max_attempts() + 1):

        try:

            db = DatabaseHandler(
                host=db_config.hostname(),
                port=db_config.port(),
                username=db_config.username(),
                password=db_config.password(),
                database=db_config.database_name(),
            )
            if not db:
                raise ValueError("Returned value is None.")

        except Exception as ex:

            error_message = "Unable to connect to %(username)s@%(host)s:%(port)d/%(database)s: %(exception)s" % {
                'username': db_config.username(),
                'host': db_config.hostname(),
                'port': db_config.port(),
                'database': db_config.database_name(),
                'exception': str(ex),
            }

            log.error(error_message)

            if attempt < retries_config.max_attempts():
                log.info(f"Will retry for #{attempt} time in {retries_config.sleep_between_attempts()} seconds...")
                time.sleep(retries_config.sleep_between_attempts())

            else:
                log.info("Out of retries, giving up...")
                raise McConnectToDBException(error_message)

    return db
