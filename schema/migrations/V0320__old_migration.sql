

CREATE OR REPLACE FUNCTION update_feeds_from_yesterday() RETURNS VOID AS $$
BEGIN

    DELETE FROM feeds_from_yesterday;
    INSERT INTO feeds_from_yesterday (feeds_id, media_id, name, url, feed_type, feed_status)
        SELECT feeds_id, media_id, name, url, feed_type, feed_status
        FROM feeds;

END;
$$
LANGUAGE 'plpgsql';



