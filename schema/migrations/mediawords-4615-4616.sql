--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4615 and 4616.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4615, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4616, import this SQL file:
--
--     psql mediacloud < mediawords-4615-4616.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

-- definition of bipolar comparisons for retweeter polarization scores
create table retweeter_scores (
    retweeter_scores_id     serial primary key,
    topics_id               int not null references topics on delete cascade,
    group_a_id              int null,
    group_b_id              int null,
    name                    text not null,
    state                   text not null default 'created but not queued',
    message                 text null
);

-- group retweeters together so that we an compare, for example, sanders/warren retweeters to cruz/kasich retweeters
create table retweeter_groups (
    retweeter_groups_id     serial primary key,
    retweeter_scores_id     int not null references retweeter_scores on delete cascade,
    name                    text not null
);

alter table retweeter_scores add constraint retweeter_scores_group_a
    foreign key ( group_a_id ) references retweeter_groups on delete cascade;
alter table retweeter_scores add constraint retweeter_scores_group_b
    foreign key ( group_b_id ) references retweeter_groups on delete cascade;

-- list of twitter users within a given topic that have retweeted the given user
create table retweeters (
    retweeters_id           serial primary key,
    retweeter_scores_id     int not null references retweeter_scores on delete cascade,
    twitter_user            varchar(1024) not null,
    retweeted_user          varchar(1024) not null
);

create unique index retweeters_user on retweeters( retweeter_scores_id, twitter_user, retweeted_user );

create table retweeter_groups_users_map (
    retweeter_groups_id     int not null references retweeter_groups on delete cascade,
    retweeter_scores_id     int not null references retweeter_scores on delete cascade,
    retweeted_user          varchar(1024) not null
);

-- count of shares by retweeters for each retweeted_user in retweeters
create table retweeter_stories (
    retweeter_shares_id     serial primary key,
    retweeter_scores_id     int not null references retweeter_scores on delete cascade,
    stories_id              int not null references stories on delete cascade,
    retweeted_user          varchar(1024) not null,
    share_count             int not null
);

create unique index retweeter_stories_psu
    on retweeter_stories ( retweeter_scores_id, stories_id, retweeted_user );

-- polarization scores for media within a topic for the given retweeter_scoresdefinition
create table retweeter_media (
    retweeter_media_id    serial primary key,
    retweeter_scores_id   int not null references retweeter_scores on delete cascade,
    media_id              int not null references media on delete cascade,
    group_a_count         int not null,
    group_b_count         int not null,
    group_a_count_n       float not null,
    score                 float not null
);

create unique index retweeter_media_score on retweeter_media ( retweeter_scores_id, media_id );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4616;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
