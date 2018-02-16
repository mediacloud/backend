--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4641 and 4642.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4641, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4642, import this SQL file:
--
--     psql mediacloud < mediawords-4641-4642.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table media_normalized_urls add db_row_last_updated timestamp not null default now();

-- update media stats table for deleted story sentence
CREATE FUNCTION update_media_db_row_last_updated() RETURNS trigger AS $$
BEGIN
    NEW.db_row_last_updated = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

create trigger update_media_db_row_last_updated before update or insert
    on media for each row execute procedure update_media_db_row_last_updated();

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4642;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
