--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4642 and 4643.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4642, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4643, import this SQL file:
--
--     psql mediacloud < mediawords-4642-4643.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--


-- update media stats table for deleted story sentence
CREATE FUNCTION update_media_db_row_last_updated() RETURNS trigger AS $$
BEGIN
    NEW.db_row_last_updated = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

create trigger update_media_db_row_last_updated before update or insert
    on media for each row execute procedure update_media_db_row_last_updated();

--- allow lookup of media by mediawords.util.url.normalized_url_lossy.
-- the data in this table is accessed and kept up to date by mediawords.tm.media.lookup_medium_by_url
create table media_normalized_urls (
    media_normalized_urls_id        serial primary key,
    media_id                        int not null references media,
    normalized_url                  varchar(1024) not null,
    db_row_last_updated             timestamp not null default now(),

    -- assigned the value of mediawords.util.url.normalized_url_lossy_version()
    normalize_url_lossy_version    int not null
);

create unique index media_normalized_urls_medium on media_normalized_urls(normalize_url_lossy_version, media_id);
create index media_normalized_urls_url on media_normalized_urls(normalized_url);

create table topic_fetch_urls(
    topic_fetch_urls_id         bigserial primary key,
    topics_id                   int not null references topics on delete cascade,
    url                         text not null,
    code                        int,
    fetch_date                  timestamp,
    state                       text not null,
    message                     text,
    stories_id                  int references stories on delete cascade,
    assume_match                boolean not null default false
);

create index topic_fetch_urls_pending on topic_fetch_urls(topics_id) where state = 'pending';

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4643;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
