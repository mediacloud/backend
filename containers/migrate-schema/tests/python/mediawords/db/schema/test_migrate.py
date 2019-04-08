import pytest

from mediawords.db.schema.migrate import (
    McSchemaVersionFromLinesException,
    _schema_version_from_lines,
)


def test_schema_version_from_lines():
    with pytest.raises(McSchemaVersionFromLinesException):
        _schema_version_from_lines('no version')

    # noinspection SqlDialectInspection,SqlNoDataSourceInspection
    assert _schema_version_from_lines("""
CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4588;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES
        ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';
    """) == 4588
