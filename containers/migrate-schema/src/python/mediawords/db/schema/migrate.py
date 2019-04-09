"""Migrate (install or update) database schema."""

import os
import re

from mediawords.db import DatabaseHandler, database_looks_empty
from mediawords.util.log import create_logger
from mediawords.util.perl import decode_object_from_bytes_if_needed

log = create_logger(__name__)

SCHEMA_DIR_PATH = '/schema/'
FULL_SCHEMA_PATH = os.path.join(SCHEMA_DIR_PATH, 'mediawords.sql')
MIGRATIONS_DIR_PATH = os.path.join(SCHEMA_DIR_PATH, 'migrations')


class McSchemaVersionFromLinesException(Exception):
    """schema_version_from_lines() exception."""
    pass


def _current_schema_version(db: DatabaseHandler) -> int:
    """Return schema version that is currently present on the connected database."""
    schema_version = db.query("""
        SELECT value AS schema_version
        FROM database_variables
        WHERE name = 'database-schema-version'
        LIMIT 1
    """).flat()
    if not schema_version:
        raise ValueError("Schema version was not found.")

    schema_version = schema_version[0]
    if not schema_version:
        raise ValueError("Schema version is zero or unset.")

    return schema_version


def _schema_version_from_lines(sql: str) -> int:
    """Utility function to determine a database schema version from a bunch of SQL commands."""

    sql = decode_object_from_bytes_if_needed(sql)

    matches = re.search(r'[+\-]*\s*MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := (\d+?);', sql)
    if matches is None:
        raise McSchemaVersionFromLinesException("Unable to parse the database schema version number")
    schema_version = int(matches.group(1))
    if schema_version == 0:
        raise McSchemaVersionFromLinesException("Invalid schema version")
    return schema_version


def migration_sql(db: DatabaseHandler) -> str:
    """Return SQL to execute to get the database to the most up-to-date version; might be an empty string."""

    if not db.in_transaction():
        raise ValueError("Caller must have started a transaction for us.")

    assert os.path.isdir(SCHEMA_DIR_PATH), f"Schema directory '{SCHEMA_DIR_PATH}' does not exist."
    assert os.path.isfile(FULL_SCHEMA_PATH), f"Full schema '{FULL_SCHEMA_PATH}' does not exist."
    assert os.path.isdir(MIGRATIONS_DIR_PATH), f"Migrations directory '{MIGRATIONS_DIR_PATH}' does not exist."

    # Load full schema
    with open(FULL_SCHEMA_PATH, mode='r', encoding='utf-8') as f:
        full_schema_sql = f.read()
        assert full_schema_sql, f"Full schema is empty."

    if database_looks_empty(db):

        log.info("Database looks empty, initializing with full schema...")
        sql = full_schema_sql

    else:

        # Work out which migrations to apply to get the schema up-to-date
        log.info("Database doesn't look empty, collecting the migrations...")
        from_version = _current_schema_version(db)
        to_version = _schema_version_from_lines(full_schema_sql)

        if from_version == to_version:
            log.info(f"Schema version {from_version} is up-to-date, nothing to do.")
            sql = ''

        elif from_version > to_version:
            raise ValueError(f"Live version ({from_version}) is newer than full schema version ({to_version}.")

        else:

            log.info(f"Will upgrade from version {from_version} to {to_version}")

            sql = f"""
                -- --------------------------------
                -- This is a concatenated schema diff between versions
                -- {from_version} and {to_version}.
                --
                -- Please review this schema diff and import it manually.
                -- --------------------------------
            """

            for migration_start_version in range(from_version, to_version):
                migration_end_version = migration_start_version + 1
                migration_file = os.path.join(
                    MIGRATIONS_DIR_PATH,
                    f"mediawords-{migration_start_version}-{migration_end_version}.sql",
                )
                if not os.path.isfile(migration_file):
                    raise ValueError(f"Migration file '{migration_file}' does not exist.")

                with open(migration_file, mode='r', encoding='utf-8') as f:
                    sql += f.read()

                sql += """
                    -- --------------------------------
                """

            # Wrap into a transaction
            if re.match(r'BEGIN;', sql, flags=re.IGNORECASE) or re.match(r'COMMIT;', sql, flags=re.IGNORECASE):
                raise ValueError(
                    "Upgrade script already BEGINs and COMMITs a transaction. Please upgrade the database manually."
                )

            sql = f"BEGIN;\n\n\n{sql}\n\n\nCOMMIT;\n"

    return sql
