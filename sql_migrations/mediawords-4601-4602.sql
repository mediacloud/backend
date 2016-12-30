--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4601 and 4602.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4601, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4602, import this SQL file:
--
--     psql mediacloud < mediawords-4601-4602.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create table media_suggestions (
    media_suggestions_id        serial primary key,
    name                        text,
    url                         text not null,
    feed_url                    text,
    reason                      text,
    auth_users_id               int references auth_users on delete set null,
    date_submitted              timestamp not null default now()
);

create index media_suggestions_date on media_suggestions ( date_submitted );

create table media_suggestions_tags_map (
    media_suggestions_id        int references media_suggestions on delete cascade,
    tags_id                     int references tags on delete cascade
);

create index media_suggestions_tags_map_ms on media_suggestions_tags_map ( media_suggestions_id );
create index media_suggestions_tags_map_tag on media_suggestions_tags_map ( tags_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4602;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
