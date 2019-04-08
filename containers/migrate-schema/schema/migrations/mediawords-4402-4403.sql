--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4402 and 4403.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4402, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4403, import this SQL file:
--
--     psql mediacloud < mediawords-4402-4403.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

DROP VIEW downloads_sites;

DROP INDEX downloads_sites_index;

DROP INDEX downloads_sites_pending;

DROP INDEX downloads_sites_downloads_id_pending;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4403;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION site_from_host("host" varchar) RETURNS varchar AS
$$
BEGIN
    RETURN regexp_replace(host, E'^(.)*?([^.]+)\\.([^.]+)$' ,E'\\2.\\3');
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE INDEX downloads_sites_index ON downloads ( site_from_host(host) );

CREATE INDEX downloads_sites_pending ON downloads ( site_from_host( host ) ) where state='pending';

CREATE UNIQUE INDEX downloads_sites_downloads_id_pending ON downloads ( site_from_host(host), downloads_id ) WHERE (state = 'pending');

CREATE VIEW downloads_sites AS
	select site_from_host( host ) as site, * from downloads_media;

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

