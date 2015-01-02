--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4474 and 4475.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4474, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4475, import this SQL file:
--
--     psql mediacloud < mediawords-4474-4475.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--
create table color_sets (
    color_sets_id               serial          primary key,
    color                       varchar( 256 )  not null,
    color_set                   varchar( 256 )  not null,
    id                          varchar( 256 )  not null
);
  
create index color_sets_set_id on color_sets ( color_set, id );
    
-- prefill colors for partisan_code set so that liberal is blue and conservative is red
insert into color_sets ( color, color_set, id ) values ( 'c10032', 'partisan_code', 'partisan_2012_conservative' );
insert into color_sets ( color, color_set, id ) values ( '00519b', 'partisan_code', 'partisan_2012_liberal' );
insert into color_sets ( color, color_set, id ) values ( '009543', 'partisan_code', 'partisan_2012_libertarian' );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4475;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


