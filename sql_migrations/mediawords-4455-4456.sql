--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4455 and 4456.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4455, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4456, import this SQL file:
--
--     psql mediacloud < mediawords-4455-4456.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


--
-- User requests (the ones that are configured to be logged)
--
CREATE TABLE auth_user_requests (

    auth_user_requests_id   SERIAL          PRIMARY KEY,

    -- User's email (does *not* reference auth_users.email because the user
    -- might be deleted)
    email                   TEXT            NOT NULL,

    -- Request path (e.g. "api/v2/stories/list")
    request_path            TEXT            NOT NULL,

    -- When did the request happen?
    request_timestamp       TIMESTAMP       NOT NULL DEFAULT LOCALTIMESTAMP,

    -- Number of "items" requested in a request
    -- For example:
    -- * a single request to "/api/v2/stories/list" would count as one item;
    -- * a single request to "/search" would count as a single request plus the
    --   number of stories if "csv=1" is specified, or just as a single request
    --   if "csv=1" is not specified
    requested_items_count   INTEGER         NOT NULL DEFAULT 1

);

CREATE INDEX auth_user_requests_email ON auth_user_requests (email);
CREATE INDEX auth_user_requests_request_path ON auth_user_requests (request_path);


--
-- User request daily counts
--
CREATE TABLE auth_user_request_daily_counts (

    auth_user_request_daily_counts_id  SERIAL  PRIMARY KEY,

    -- User's email (does *not* reference auth_users.email because the user
    -- might be deleted)
    email                   TEXT            NOT NULL,

    -- Day (request timestamp, date_truncated to a day)
    day                     TIMESTAMP       NOT NULL,

    -- Number of requests
    requests_count          INTEGER         NOT NULL,

    -- Number of requested items
    requested_items_count   INTEGER         NOT NULL

);

CREATE INDEX auth_user_request_daily_counts_email ON auth_user_request_daily_counts (email);
CREATE INDEX auth_user_request_daily_counts_day ON auth_user_request_daily_counts (day);


-- On each logged request, update "auth_user_request_daily_counts" table
CREATE OR REPLACE FUNCTION auth_user_requests_update_daily_counts() RETURNS trigger AS
$$

DECLARE
    day_timestamp DATE;

BEGIN

    day_timestamp := DATE_TRUNC('day', NEW.request_timestamp);

    -- Try to UPDATE a previously INSERTed day
    UPDATE auth_user_request_daily_counts
    SET requests_count = requests_count + 1,
        requested_items_count = requested_items_count + NEW.requested_items_count
    WHERE email = NEW.email
      AND day = day_timestamp;

    IF FOUND THEN
        RETURN NULL;
    END IF;

    -- If UPDATE was not successful, do an INSERT (new day!)
    INSERT INTO auth_user_request_daily_counts (email, day, requests_count, requested_items_count)
    VALUES (NEW.email, day_timestamp, 1, NEW.requested_items_count);

    RETURN NULL;

END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER auth_user_requests_update_daily_counts
    AFTER INSERT ON auth_user_requests
    FOR EACH ROW EXECUTE PROCEDURE auth_user_requests_update_daily_counts();



CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4456;
    
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

