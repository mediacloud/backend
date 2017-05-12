--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4617 and 4618.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4617, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4618, import this SQL file:
--
--     psql mediacloud < mediawords-4617-4618.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

-- log of all stories import into solr, with the import date
create table solr_imported_stories (
    stories_id          int not null references stories on delete cascade,
    import_date         timestamp not null
);

create index solr_imported_stories_story on solr_imported_stories ( stories_id );
create index solr_imported_stories_day on solr_imported_stories ( date_trunc( 'day', import_date ) );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4618;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
