--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4509 and 4510.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4509, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4510, import this SQL file:
--
--     psql mediacloud < mediawords-4509-4510.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table controversy_seed_urls add publish_date text;
alter table controversy_seed_urls add title text;
alter table controversy_seed_urls add guid text;
alter table controversy_seed_urls add content text;
alter table controversies add max_iterations int not null default 15;


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4511;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
