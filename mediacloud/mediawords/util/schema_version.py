import re

from mediawords.util.perl import decode_string_from_bytes_if_needed


class SchemaVersionFromLinesException(Exception):
    pass


def schema_version_from_lines(sql):
    """Utility function to determine a database schema version from a bunch of SQL commands."""
    sql = decode_string_from_bytes_if_needed(sql)
    matches = re.search(r'[+\-]*\s*MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := (\d+?);', sql)
    if matches is None:
        raise SchemaVersionFromLinesException("Unable to parse the database schema version number")
    schema_version = int(matches.group(1))
    if schema_version == 0:
        raise SchemaVersionFromLinesException("Invalid schema version")
    return schema_version
