--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4465 and 4466.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4465, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4466, import this SQL file:
--
--     psql mediacloud < mediawords-4465-4466.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create function insert_controversy_tag_set() returns trigger as $insert_controversy_tag_set$
    begin
        insert into tag_sets ( name, label, description )
            select 'controversy_'||NEW.name, NEW.name||' controversy', 'Tag set for stories within the '||NEW.name||' controversy.';
        
        select tag_sets_id into NEW.controversy_tag_sets_id from tag_sets where name = 'controversy_'||NEW.name;

        return NEW;
    END;
$insert_controversy_tag_set$ LANGUAGE plpgsql;

create trigger controversy_tag_set before insert on controversies
    for each row execute procedure insert_controversy_tag_set();         

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4466;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


