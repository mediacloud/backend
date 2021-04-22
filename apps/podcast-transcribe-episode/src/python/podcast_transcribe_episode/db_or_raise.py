from mediawords.db import connect_to_db, DatabaseHandler

from mediawords.util.config.common import DatabaseConfig, ConnectRetriesConfig


def connect_to_db_or_raise() -> DatabaseHandler:
    """
    Shorthand for connect_to_db() with its own retries and fatal_error() disabled.

    By default, connect_to_db() will attempt connecting to PostgreSQL a few times and would call fatal_error() on
    failures and stop the whole process.

    We leave retrying and failure handling to Temporal here so we disable all of this functionality.

    FIXME probably move to "common".
    """
    return connect_to_db(
        db_config=DatabaseConfig(
            retries=ConnectRetriesConfig(
                max_attempts=1,
                fatal_error_on_failure=False,
            )
        )
    )
