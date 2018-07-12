--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4600 and 4601.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4600, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4601, import this SQL file:
--
--     psql mediacloud < mediawords-4600-4601.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


create table media_stats_weekly (
    media_id        int not null references media on delete cascade,
    stories_rank    int not null,
    num_stories     numeric not null,
    sentences_rank  int not null,
    num_sentences   numeric not null,
    stat_week       date not null
);

create index media_stats_weekly_medium on media_stats_weekly ( media_id );

create table media_expected_volume (
    media_id            int not null references media on delete cascade,
    start_date          date not null,
    end_date            date not null,
    expected_stories    numeric not null,
    expected_sentences  numeric not null
);

create index media_expected_volume_medium on media_expected_volume ( media_id );

create table media_coverage_gaps (
    media_id                int not null references media on delete cascade,
    stat_week               date not null,
    num_stories             numeric not null,
    expected_stories        numeric not null,
    num_sentences           numeric not null,
    expected_sentences      numeric not null
);

create index media_coverage_gaps_medium on media_coverage_gaps ( media_id );

create table media_health (
    media_id            int not null references media on delete cascade,
    num_stories         numeric not null,
    num_stories_y       numeric not null,
    num_stories_w       numeric not null,
    num_stories_90      numeric not null,
    num_sentences       numeric not null,
    num_sentences_y     numeric not null,
    num_sentences_w     numeric not null,
    num_sentences_90    numeric not null,
    is_healthy          boolean not null default false,
    has_active_feed     boolean not null default true,
    start_date          date not null,
    end_date            date not null,
    expected_sentences  numeric not null,
    expected_stories    numeric not null,
    coverage_gaps       int not null
);

create index media_health_medium on media_health ( media_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4601;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
