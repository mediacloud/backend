import re

from mediawords.util.perl import decode_object_from_bytes_if_needed


class McSchemaVersionFromLinesException(Exception):
    pass


def schema_version_from_lines(sql: str) -> int:
    """Utility function to determine a database schema version from a bunch of SQL commands."""

    sql = decode_object_from_bytes_if_needed(sql)

    matches = re.search(r'[+\-]*\s*MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := (\d+?);', sql)
    if matches is None:
        raise McSchemaVersionFromLinesException("Unable to parse the database schema version number")
    schema_version = int(matches.group(1))
    if schema_version == 0:
        raise McSchemaVersionFromLinesException("Invalid schema version")
    return schema_version
