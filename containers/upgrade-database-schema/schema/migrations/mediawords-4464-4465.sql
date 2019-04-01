--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4464 and 4465.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4464, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4465, import this SQL file:
--
--     psql mediacloud < mediawords-4464-4465.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table controversies add controversy_tag_sets_id int references tag_sets;

update controversies c set controversy_tag_sets_id = ts.tag_sets_id
    from tag_sets ts
    where ts.name = 'controversy_' || c.name;
    
alter table controversies alter controversy_tag_sets_id set not null;

alter table controversies add media_type_tag_sets_id int references tag_sets;

create unique index controversies_tag_set on controversies( controversy_tag_sets_id );
create unique index controversies_media_type_tag_set on controversies( media_type_tag_sets_id );


--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4465;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


