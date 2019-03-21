


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



