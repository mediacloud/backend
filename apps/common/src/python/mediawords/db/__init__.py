import time

from mediawords.db.handler import DatabaseHandler
from mediawords.util.config.common import CommonConfig
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)


class McConnectToDBException(Exception):
    """connect_to_db() exception."""
    pass


def database_looks_empty(db: DatabaseHandler) -> bool:
    """Returns True if the database looks empty."""
    stories_tables = db.query("""
        SELECT 1
        FROM information_schema.tables 
        WHERE table_schema = 'public'
          AND table_name = 'stories' 
    """).flat()
    if len(stories_tables) > 0:
        return False
    else:
        return True


def connect_to_db(require_schema: bool = True) -> DatabaseHandler:
    """Connect to PostgreSQL."""

    if isinstance(require_schema, bytes):
        require_schema = decode_object_from_bytes_if_needed(require_schema)

    require_schema = bool(int(require_schema))

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

            if require_schema:
                if database_looks_empty(db):
                    raise ValueError("Connection succeeded but the database is empty.")

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
