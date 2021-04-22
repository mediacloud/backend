import time
from typing import Optional

from mediawords.db.handler import DatabaseHandler
from mediawords.util.config.common import CommonConfig, DatabaseConfig
from mediawords.util.log import create_logger
from mediawords.util.process import fatal_error

log = create_logger(__name__)


class McConnectToDBError(Exception):
    """Exception that gets raised if connect_to_db() runs out of retries and
    db_config.retries.fatal_error_on_failure is set to False."""
    pass


def connect_to_db(db_config: Optional[DatabaseConfig] = None) -> DatabaseHandler:
    """
    Connect to PostgreSQL (via PgBouncer).

    :param db_config: Optional DatabaseConfig parameter to specify connection retry parameters.
    :return: DatabaseHandler object.
    """

    if not db_config:
        db_config = CommonConfig.database()

    retries_config = db_config.retries()

    assert retries_config.max_attempts() > 0, "max_tries can't be negative."

    db = None

    for attempt in range(1, retries_config.max_attempts() + 1):

        try:

            log.debug("Connecting to PostgreSQL...")

            db = DatabaseHandler(
                host=db_config.hostname(),
                port=db_config.port(),
                username=db_config.username(),
                password=db_config.password(),
                database=db_config.database_name(),
            )
            if not db:
                raise ValueError("Returned value is None.")

            # Return the database handler upon successful connection
            break

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
                log.info("Out of retries, giving up and exiting...")

                if retries_config.fatal_error_on_failure():
                    # Don't throw any exceptions because they might be caught by
                    # the try-catch block, and so the caller will just assume that
                    # there was something wrong with the input data and proceed
                    # with processing next item in the job queue (e.g. the next
                    # story). Instead, just quit and wait for someone to restart
                    # the whole app that requires database access.
                    fatal_error(error_message)
                else:
                    raise McConnectToDBError(error_message)

    return db
