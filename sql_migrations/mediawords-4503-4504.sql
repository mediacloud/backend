--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4503 and 4504.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4503, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4504, import this SQL file:
--
--     psql mediacloud < mediawords-4503-4504.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- On each logged request, update "auth_user_request_daily_counts" table
CREATE OR REPLACE FUNCTION auth_user_requests_update_daily_counts() RETURNS trigger AS
$$

DECLARE
    request_date DATE;

BEGIN

    -- Try to prevent deadlocks
    LOCK TABLE auth_user_request_daily_counts IN SHARE ROW EXCLUSIVE MODE;

    request_date := DATE_TRUNC('day', NEW.request_timestamp)::DATE;

    WITH upsert AS (
        -- Try to UPDATE a previously INSERTed day
        UPDATE auth_user_request_daily_counts
        SET requests_count = requests_count + 1,
            requested_items_count = requested_items_count + NEW.requested_items_count
        WHERE email = NEW.email
          AND day = request_date
        RETURNING *
    )
    INSERT INTO auth_user_request_daily_counts (email, day, requests_count, requested_items_count)
        SELECT NEW.email, request_date, 1, NEW.requested_items_count
        WHERE NOT EXISTS (
            SELECT *
            FROM upsert
        );

    RETURN NULL;

END;
$$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4504;
    
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

