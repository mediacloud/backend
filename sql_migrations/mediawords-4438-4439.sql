--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4438 and 4439.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4438, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4439, import this SQL file:
--
--     psql mediacloud < mediawords-4438-4439.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

create table media_stats (
    media_stats_id              serial      primary key,
    media_id                    int         not null references media on delete cascade,
    num_stories                 int         not null,
    num_sentences               int         not null,
    mean_num_sentences          int         not null,
    mean_text_length            int         not null,
    num_stories_with_sentences  int         not null,
    num_stories_with_text       int         not null,
    stat_date                   date        not null
);

create index media_stats_medium on media_stats( media_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4439;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


