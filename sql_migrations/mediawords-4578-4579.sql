--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4578 and 4579.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4578, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4579, import this SQL file:
--
--     psql mediacloud < mediawords-4578-4579.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

-- keep track of performance of the topic spider
create table topic_spider_metrics (
    topic_spider_metrics_id         serial primary key,
    topics_id                       int references topics on delete cascade,
    iteration                       int not null,
    links_processed                 int not null,
    elapsed_time                    int not null,
    processed_date                  timestamp not null default now()
);

create index topic_spider_metrics_topic on topic_spider_metrics( topics_id );
create index topic_spider_metrics_dat on topic_spider_metrics( processed_date );

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4579;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
