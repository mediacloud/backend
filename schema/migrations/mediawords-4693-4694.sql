--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4693 and 4694.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4693, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4694, import this SQL file:
--
--     psql mediacloud < mediawords-4693-4694.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


CREATE TYPE media_sitemap_pages_change_frequency AS ENUM (
    'always',
    'hourly',
    'daily',
    'weekly',
    'monthly',
    'yearly',
    'never'
);


-- Pages derived from XML sitemaps (stories or not)
CREATE TABLE media_sitemap_pages (
    media_sitemap_pages_id  BIGSERIAL   PRIMARY KEY,
    media_id                INT         NOT NULL REFERENCES media (media_id) ON DELETE CASCADE,

    -- <loc> -- URL of the page
    url                     TEXT                                  NOT NULL,

    -- <lastmod> -- date of last modification of the URL
    last_modified           TIMESTAMP WITH TIME ZONE              NULL,

    -- <changefreq> -- how frequently the page is likely to change
    change_frequency        media_sitemap_pages_change_frequency  NULL,

    -- <priority> -- priority of this URL relative to other URLs on your site
    priority                DECIMAL(2, 1)                         NOT NULL DEFAULT 0.5,

    -- <news:title> -- title of the news article
    news_title              TEXT                                  NULL,

    -- <news:publication_date> -- article publication date
    news_publish_date       TIMESTAMP WITH TIME ZONE              NULL,

    CONSTRAINT media_sitemap_pages_priority_within_bounds
        CHECK (priority IS NULL OR (priority >= 0.0 AND priority <= 1.0))

);

CREATE UNIQUE INDEX media_sitemap_pages_url
    ON media_sitemap_pages (url);


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4694;
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();
