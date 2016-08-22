--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4577 and 4578.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4577, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4578, import this SQL file:
--
--     psql mediacloud < mediawords-4577-4578.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

-- it's better to have a few duplicates than deal with locking issues, so we don't try to make this unique
create index cached_extractor_results_downloads_id on cached_extractor_results( downloads_id );

alter table cached_extractor_results alter downloads_id set not null;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4578;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
