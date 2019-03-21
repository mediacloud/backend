


CREATE OR REPLACE FUNCTION upsert_bitly_clicks_total(param_stories_id INT, param_click_count INT) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE bitly_clicks_total
            SET click_count = param_click_count
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_clicks_total (stories_id, click_count)
            VALUES (param_stories_id, param_click_count);
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


