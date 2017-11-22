--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4637 and 4638.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4637, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4638, import this SQL file:
--
--     psql mediacloud < mediawords-4637-4638.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Delete duplicate users (the non-lowercase emails)
DELETE FROM auth_user_request_daily_counts
WHERE email IN (
    SELECT email
    FROM auth_users
    WHERE LOWER(email) IN (

        -- Users with duplicate emails
        SELECT LOWER(email)
        FROM auth_users
        GROUP BY LOWER(email)
        HAVING COUNT(*) > 1
    )

      -- Emails that are not lowercase
      AND email::text != lower(email)::text
);

DELETE FROM auth_users
WHERE email IN (
    SELECT email
    FROM auth_users
    WHERE LOWER(email) IN (

        -- Users with duplicate emails
        SELECT LOWER(email)
        FROM auth_users
        GROUP BY LOWER(email)
        HAVING COUNT(*) > 1
    )

      -- Emails that are not lowercase
      AND email::text != lower(email)::text
);


CREATE EXTENSION IF NOT EXISTS citext SCHEMA public;
CREATE EXTENSION IF NOT EXISTS citext SCHEMA snap;

DROP FUNCTION auth_user_limits_weekly_usage(user_email TEXT);

ALTER TABLE auth_users
    ALTER COLUMN email TYPE CITEXT;

ALTER TABLE auth_user_request_daily_counts
    ALTER COLUMN email TYPE CITEXT;

ALTER TABLE activities
    ALTER COLUMN user_identifier TYPE CITEXT;


CREATE OR REPLACE FUNCTION auth_user_limits_weekly_usage(user_email CITEXT) RETURNS TABLE(email CITEXT, weekly_requests_sum BIGINT, weekly_requested_items_sum BIGINT) AS
$$

    SELECT auth_users.email,
           COALESCE(SUM(auth_user_request_daily_counts.requests_count), 0) AS weekly_requests_sum,
           COALESCE(SUM(auth_user_request_daily_counts.requested_items_count), 0) AS weekly_requested_items_sum
    FROM auth_users
        LEFT JOIN auth_user_request_daily_counts
            ON auth_users.email = auth_user_request_daily_counts.email
            AND auth_user_request_daily_counts.day > DATE_TRUNC('day', NOW())::date - INTERVAL '1 week'
    WHERE auth_users.email = $1
    GROUP BY auth_users.email;

$$
LANGUAGE SQL;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4638;

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

