--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4739 and 4740.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4739, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4740, import this SQL file:
--
--     psql mediacloud < mediawords-4739-4740.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

-- the mode is how we analyze the data from the platform (as web pages, social media posts, url sharing posts, etc)
create table topic_modes (
    topic_modes_id          serial primary key,
    name                    varchar(1024) not null unique,
    description             text not null
);

create unique index topic_modes_name on topic_modes(name);

insert into topic_modes ( name, description ) values

    ('web', 'analyze urls using hyperlinks as network edges'),
    ('url_sharing', 'analyze urls shared on social media using co-sharing as network edges');

-- the platform is where the analyzed data lives (web, twitter, reddit, etc)
create table topic_platforms (
    topic_platforms_id      serial primary key,
    name                    varchar(1024) not null unique,
    description             text not null
);

create unique index topic_platforms_name on topic_platforms(name);

insert into topic_platforms (name, description) values
    ('web', 'pages on the open web'),
    ('twitter', 'tweets from twitter.com'),
    ('generic_post', 'generic social media posts'),
    ('reddit', 'submissions and comments from reddit.com');

-- the source is where we get the platforn data from (a particular database, api, csv, etc)
create table topic_sources (
    topic_sources_id        serial primary key,
    name                    varchar(1024) not null unique,
    description             text not null
);

create unique index topic_sources_name on topic_sources(name);

insert into topic_sources ( name, description ) values
    ('mediacloud', 'import from the mediacloud.org archive'),
    ('crimson_hexagon', 'import from the crimsonhexagon.com forsight api, only accessible to internal media cloud team'),
    ('csv', 'import generic posts directly from csv'),
    ('pushshift', 'import from the pushshift.io api');

-- the pairs of platforms / sources for which the platform can fetch data
create table topic_platforms_sources_map (
    topic_platforms_id      int not null references topic_platforms on delete cascade,
    topic_sources_id        int not null references topic_sources on delete cascade
);

create unique index topic_platforms_sources_map_ps
    on topic_platforms_sources_map ( topic_platforms_id, topic_sources_id );

-- easily create platform source pairs
create function insert_platform_source_pair( text, text ) returns void as $$
    insert into topic_platforms_sources_map ( topic_platforms_id, topic_sources_id )
        select 
                tp.topic_platforms_id,
                ts.topic_sources_id
            from
                topic_platforms tp
                cross join topic_sources ts
            where
                tp.name = $1  and
                ts.name = $2
$$ language sql;

select insert_platform_source_pair( 'web', 'mediacloud' );
select insert_platform_source_pair( 'twitter', 'crimson_hexagon' );
select insert_platform_source_pair( 'generic_post', 'csv' );
select insert_platform_source_pair( 'reddit', 'pushshift' );

drop view topic_post_full_urls;

alter table topics alter platform type text;
alter table topics add foreign key ( platform ) references topic_platforms ( name );
alter table topics alter platform set default 'web';

alter table topics alter mode type text;
alter table topics add foreign key ( mode ) references topic_modes ( name );
alter table topics alter mode set default 'web';

alter table topic_seed_queries alter platform type text;
alter table topic_seed_queries add foreign key ( platform ) references topic_platforms ( name );

alter table topic_seed_queries alter source type text;
alter table topic_seed_queries add foreign key ( source ) references topic_sources ( name );

alter table topic_seed_urls add topic_seed_queries_id int null references topic_seed_queries on delete cascade;

alter table topic_post_days add topic_seed_queries_id int references topic_seed_queries on delete cascade;

update topic_post_days tpd 
    set topic_seed_queries_id = tsq.topic_seed_queries_id
    from topic_seed_queries tsq
    where tsq.topics_id = tpd.topics_id;

drop index topic_post_days_td;

alter table topic_post_days drop topics_id;

alter table topic_post_days alter topic_seed_queries_id set not null;

create index topic_post_days_td on ( topic_seed_queries_id, day );

create view topic_post_full_urls as
    select distinct
            t.topics_id,
            tt.topic_posts_id, tt.content, tt.publish_date, tt.author,
            ttd.day, ttd.num_posts, ttd.posts_fetched,
            ttu.url, tsu.stories_id
        from
            topics t
            join topic_seed_queries tsq using ( topics_id )
            join topic_post_days ttd using ( topic_seed_queries_id )
            join topic_posts tt using ( topic_post_days_id )
            join topic_post_urls ttu using ( topic_posts_id )
            left join topic_seed_urls tsu
                on ( tsu.topics_id = t.topics_id and ttu.url = tsu.url );

drop type topic_platform_type;
drop type topic_source_type;
drop type topic_mode_type;

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4740;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


