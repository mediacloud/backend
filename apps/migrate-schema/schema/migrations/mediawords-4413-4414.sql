--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4413 and 4414.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4413, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4414, import this SQL file:
--
--     psql mediacloud < mediawords-4413-4414.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4414;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

create view controversy_links_cross_media as
  select s.stories_id, sm.name as media_name, r.stories_id as ref_stories_id, rm.name as ref_media_name, cl.url as url, cs.controversies_id, cl.controversy_links_id from media sm, media rm, controversy_links cl, stories s, stories r, controversy_stories cs where cl.ref_stories_id <> cl.stories_id and s.stories_id = cl.stories_id and cl.ref_stories_id = r.stories_id and s.media_id <> r.media_id and sm.media_id = s.media_id and rm.media_id = r.media_id and cs.stories_id = cl.ref_stories_id and cs.controversies_id = cl.controversies_id;

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();
