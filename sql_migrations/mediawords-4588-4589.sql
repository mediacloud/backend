--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4588 and 4589.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4588, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4589, import this SQL file:
--
--     psql mediacloud < mediawords-4588-4589.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

alter table topics add is_public boolean not null default false;

create type topic_permission AS ENUM ( 'read', 'write', 'admin' );

-- per user permissions for topics
create table topic_permissions (
    topic_permissions_id    serial primary key,
    topics_id               int not null references topics on delete cascade,
    auth_users_id           int not null references auth_users on delete cascade,
    permission              topic_permission not null
);

create index topic_permissions_topic on topic_permissions( topics_id );
create unique index topic_permissions_user on topic_permissions( auth_users_id, topics_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4589;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
