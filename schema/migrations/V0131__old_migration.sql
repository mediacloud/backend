


DROP FUNCTION IF EXISTS upsert_story_bitly_statistics(INT, INT, INT);
CREATE OR REPLACE FUNCTION upsert_story_bitly_statistics(param_stories_id INT, param_bitly_click_count INT) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE story_bitly_statistics
            SET bitly_click_count = param_bitly_click_count
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO story_bitly_statistics (stories_id, bitly_click_count)
            VALUES (param_stories_id, param_bitly_click_count);
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


-- Copy the referrer counts to a legacy table
create table story_statistics_bitly_referrers (
    story_statistics_id         serial      primary key,
    stories_id                  int         not null references stories on delete cascade,

    bitly_referrer_count        int         null
);

create unique index story_statistics_bitly_referrers_story on story_statistics_bitly_referrers ( stories_id );

INSERT INTO story_statistics_bitly_referrers (stories_id, bitly_referrer_count)
    SELECT stories_id, bitly_referrer_count
    FROM story_bitly_statistics;


ALTER TABLE story_bitly_statistics
	DROP COLUMN bitly_referrer_count;

ALTER TABLE cd.story_link_counts
    DROP COLUMN bitly_referrer_count;

ALTER TABLE cd.medium_link_counts
    DROP COLUMN bitly_referrer_count;


