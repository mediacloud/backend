


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



