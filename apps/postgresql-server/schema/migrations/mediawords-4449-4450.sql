--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4449 and 4450.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4449, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4450, import this SQL file:
--
--     psql mediacloud < mediawords-4449-4450.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create index auth_users_email on auth_users( email );
create index auth_users_token on auth_users( api_token );

create table auth_user_ip_tokens (
    auth_user_ip_tokens_id  serial      primary key,
    auth_users_id           int         not null references auth_users on delete cascade,
    api_token               varchar(64) unique not null default generate_api_token() constraint api_token_64_characters check( length( api_token ) = 64 ),
    ip_address              inet    not null
);

create index auth_user_ip_tokens_token on auth_user_ip_tokens ( api_token, ip_address );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4450;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


