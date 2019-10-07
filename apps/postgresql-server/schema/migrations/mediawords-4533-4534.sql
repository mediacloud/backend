--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4533 and 4534.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4533, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4534, import this SQL file:
--
--     psql mediacloud < mediawords-4533-4534.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

-- dates on which feeds have been scraped with MediaWords::ImportStories and the module used for scraping
create table scraped_feeds (
    scraped_feeds_id        serial primary key,
    feeds_id                int not null references feeds on delete cascade,
    scrape_date             timestamp not null default now(),
    import_module           text not null
);

create index scraped_feeds_feed on scraped_feeds ( feeds_id );

create view feedly_unscraped_feeds as
    select f.*
        from feeds f
            left join scraped_feeds sf on
                ( f.feeds_id = sf.feeds_id and sf.import_module = 'MediaWords::ImportStories::Feedly' )
        where
            f.feed_type = 'syndicated' and
            f.feed_status = 'active' and
            sf.feeds_id is null;
            
--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4534;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
