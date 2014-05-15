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

-- User limits for logged + throttled controller actions
CREATE TABLE auth_user_limits (

    auth_user_limits_id             SERIAL      NOT NULL,

    auth_users_id                   INTEGER     NOT NULL UNIQUE REFERENCES auth_users(auth_users_id)
                                                ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE,

    -- Request limit (0 or belonging to 'admin' / 'admin-readonly' group = no
    -- limit)
    weekly_requests_limit           INTEGER     NOT NULL DEFAULT 1000,

    -- Requested items (stories) limit (0 or belonging to 'admin' /
    -- 'admin-readonly' group = no limit)
    weekly_requested_items_limit    INTEGER     NOT NULL DEFAULT 20000

);

CREATE UNIQUE INDEX auth_user_limits_auth_users_id ON auth_user_limits (auth_users_id);

-- Set the default limits for newly created users
CREATE OR REPLACE FUNCTION auth_users_set_default_limits() RETURNS trigger AS
$$
BEGIN

    INSERT INTO auth_user_limits (auth_users_id) VALUES (NEW.auth_users_id);
    RETURN NULL;

END;
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER auth_users_set_default_limits
    AFTER INSERT ON auth_users
    FOR EACH ROW EXECUTE PROCEDURE auth_users_set_default_limits();


-- Add helper function to find out weekly request / request items usage for a user
CREATE OR REPLACE FUNCTION auth_user_limits_weekly_usage(user_email TEXT)
RETURNS TABLE(email TEXT, weekly_requests_sum BIGINT, weekly_requested_items_sum BIGINT) AS
$$

    SELECT auth_users.email,
           COALESCE(SUM(auth_user_request_daily_counts.requests_count), 0) AS weekly_requests_sum,
           COALESCE(SUM(auth_user_request_daily_counts.requested_items_count), 0) AS weekly_requested_items_sum
    FROM auth_users
        LEFT JOIN auth_user_request_daily_counts
            ON auth_users.email = auth_user_request_daily_counts.email
            AND auth_user_request_daily_counts.day > DATE_TRUNC('day', NOW()) - INTERVAL '1 week'
    WHERE auth_users.email = $1
    GROUP BY auth_users.email;

$$
LANGUAGE SQL;


-- Set default limits to the previously created users by creating a temporary ON UPDATE trigger
CREATE TRIGGER auth_users_set_default_limits_for_previously_created_users
    AFTER UPDATE ON auth_users
    FOR EACH ROW EXECUTE PROCEDURE auth_users_set_default_limits();

-- Run UPDATE trigger against all of the previously created users (that don't have their limit set yet)
UPDATE auth_users
SET auth_users_id = auth_users_id
WHERE NOT EXISTS (
    SELECT 1
    FROM auth_user_limits
    WHERE auth_users_id = auth_users.auth_users_id
);

DROP TRIGGER auth_users_set_default_limits_for_previously_created_users ON auth_users;


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

