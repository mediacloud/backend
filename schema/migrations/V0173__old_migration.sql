


DROP FUNCTION upsert_bitly_clicks_total(param_stories_id INT, param_click_count INT);

CREATE OR REPLACE FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "bitly_clicks_total_000001")
BEGIN
    SELECT bitly_get_partition_name( NEW.stories_id, 'bitly_clicks_total' ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ON CONFLICT (stories_id) DO UPDATE
            SET click_count = EXCLUDED.click_count
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;




