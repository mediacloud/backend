--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4646 and 4647.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4646, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4647, import this SQL file:
--
--     psql mediacloud < mediawords-4646-4647.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table topic_fetch_urls add topic_links_id int references topic_links on delete cascade;

create index topic_fetch_urls_url on topic_fetch_urls(url);

update topic_links set link_spidered = 't' where ref_stories_id is null;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4647;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
