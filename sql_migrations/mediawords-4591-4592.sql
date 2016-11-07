--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4591 and 4592.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4591, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4592, import this SQL file:
--
--     psql mediacloud < mediawords-4591-4592.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter index snap.story_link_counts_story rename to story_link_counts_ts;
create index story_link_counts_story on snap.story_link_counts( stories_id );

alter table snapshots add searchable boolean not null default false;

update snapshots set searchable = true;

create index snapshots_searchable on snapshots ( searchable );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4592;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
