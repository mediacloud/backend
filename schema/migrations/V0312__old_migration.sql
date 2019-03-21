


-- Remove duplicates that could have been created due to race conditions and whatnot
DELETE FROM auth_user_request_daily_counts
WHERE auth_user_request_daily_counts_id IN (
    SELECT auth_user_request_daily_counts_id
    FROM (
        SELECT auth_user_request_daily_counts_id,
               ROW_NUMBER() OVER (partition BY email, day ORDER BY auth_user_request_daily_counts_id) AS row_number
        FROM auth_user_request_daily_counts) AS auth_user_request_daily_counts
    WHERE auth_user_request_daily_counts.row_number > 1);


DROP INDEX IF EXISTS auth_user_request_daily_counts_email;
DROP INDEX IF EXISTS auth_user_request_daily_counts_day;

CREATE OR REPLACE FUNCTION upsert_auth_user_request_daily_counts(param_email TEXT, param_requested_items_count INT) RETURNS VOID AS
$$
DECLARE
    request_date DATE;
BEGIN
    request_date := DATE_TRUNC('day', LOCALTIMESTAMP)::DATE;

    LOOP
        -- Try UPDATing
        UPDATE auth_user_request_daily_counts
           SET requests_count = requests_count + 1,
               requested_items_count = requested_items_count + param_requested_items_count
         WHERE email = param_email
           AND day = request_date;

        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO auth_user_request_daily_counts (email, day, requests_count, requested_items_count)
            VALUES (param_email, request_date, 1, param_requested_items_count);
            RETURN;
        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;



CREATE UNIQUE INDEX auth_user_request_daily_counts_email_day ON auth_user_request_daily_counts (email, day);

