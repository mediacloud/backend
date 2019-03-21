


ALTER TABLE cd.story_bitly_statistics
    SET SCHEMA public;

DROP FUNCTION cd.all_controversy_stories_have_bitly_statistics (INT);


-- Recreate function because both the schema and the definition changes
DROP FUNCTION cd.upsert_story_bitly_statistics (INT, INT, INT);
CREATE FUNCTION upsert_story_bitly_statistics (
    param_stories_id INT,
    param_bitly_click_count INT,
    param_bitly_referrer_count INT
) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE story_bitly_statistics
            SET bitly_click_count = param_bitly_click_count,
                bitly_referrer_count = param_bitly_referrer_count
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO story_bitly_statistics (stories_id, bitly_click_count, bitly_referrer_count)
            VALUES (param_stories_id, param_bitly_click_count, param_bitly_referrer_count);
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

-- Helper to return a number of stories for which we don't have Bit.ly statistics yet
CREATE FUNCTION num_controversy_stories_without_bitly_statistics (param_controversies_id INT) RETURNS INT AS
$$
DECLARE
    controversy_exists BOOL;
    num_stories_without_bitly_statistics INT;
BEGIN

    SELECT 1 INTO controversy_exists
    FROM controversies
    WHERE controversies_id = param_controversies_id
      AND process_with_bitly = 't';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Controversy % does not exist or is not set up for Bit.ly processing.', param_controversies_id;
        RETURN FALSE;
    END IF;

    SELECT COUNT(stories_id) INTO num_stories_without_bitly_statistics
    FROM controversy_stories
    WHERE controversies_id = param_controversies_id
      AND stories_id NOT IN (
        SELECT stories_id
        FROM story_bitly_statistics
    )
    GROUP BY controversies_id;
    IF NOT FOUND THEN
        num_stories_without_bitly_statistics := 0;
    END IF;

    RETURN num_stories_without_bitly_statistics;
END;
$$
LANGUAGE plpgsql;




