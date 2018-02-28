--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4645 and 4646.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4645, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4646, import this SQL file:
--
--     psql mediacloud < mediawords-4645-4646.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--
--
-- SimilarWeb metrics
--
CREATE TABLE similarweb_metrics (
    similarweb_metrics_id  SERIAL                   PRIMARY KEY,
    domain                 VARCHAR(1024)            NOT NULL,
    month                  DATE,
    visits                 INTEGER,
    update_date            TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (domain, month)
);


--
-- Unnormalized table
--
CREATE TABLE similarweb_media_metrics (
    similarweb_media_metrics_id    SERIAL                   PRIMARY KEY,
    media_id                       INTEGER                  UNIQUE NOT NULL references media,
    similarweb_domain              VARCHAR(1024)            NOT NULL,
    domain_exact_match             BOOLEAN                  NOT NULL,
    monthly_audience               INTEGER                  NOT NULL,
    update_date                    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE

    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4646;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();
