--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4486 and 4487.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4486, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4487, import this SQL file:
--
--     psql mediacloud < mediawords-4486-4487.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE TABLE auth_users_tag_sets_permissions (
	auth_users_tag_sets_permissions_id SERIAL  PRIMARY KEY,
	auth_users_id integer references auth_users NOT NULL,
	tag_sets_id integer references tag_sets NOT NULL,
	apply_tags boolean NOT NULL,
	create_tags boolean NOT NULL,
	edit_tag_set_descriptors boolean NOT NULL,
	edit_tag_descriptors boolean NOT NULL
);

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4487;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE UNIQUE INDEX auth_users_tag_sets_permissions_auth_user_tag_set ON auth_users_tag_sets_permissions ( auth_users_id , tag_sets_id );

CREATE UNIQUE INDEX auth_users_tag_sets_permissions_auth_user ON auth_users_tag_sets_permissions ( auth_users_id );

CREATE UNIQUE INDEX auth_users_tag_sets_permissions_tag_sets ON auth_users_tag_sets_permissions ( tag_sets_id );

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

