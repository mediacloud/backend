


-- Recreate the trigger in case it doesn't exist
CREATE OR REPLACE FUNCTION bitly_clicks_total_partition_by_stories_id_insert_trigger()
RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;
BEGIN
    SELECT bitly_get_partition_name( NEW.stories_id, 'bitly_clicks_total' ) INTO target_table_name;
    EXECUTE 'INSERT INTO ' || target_table_name || ' SELECT $1.*;' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS bitly_clicks_total_partition_by_stories_id_insert_trigger ON bitly_clicks_total;
CREATE TRIGGER bitly_clicks_total_partition_by_stories_id_insert_trigger
    BEFORE INSERT ON bitly_clicks_total
    FOR EACH ROW EXECUTE PROCEDURE bitly_clicks_total_partition_by_stories_id_insert_trigger();


-- Move data that errorneously got into the master table to partitions
CREATE TEMPORARY TABLE temp_bitly_clicks_total_master_table (
    stories_id BIGINT NOT NULL,
    click_count INT NOT NULL
);
INSERT INTO temp_bitly_clicks_total_master_table (stories_id, click_count)
    SELECT stories_id, click_count
    FROM ONLY bitly_clicks_total;   -- ONLY the master table, not partitions
TRUNCATE ONLY bitly_clicks_total;   -- ONLY the master table, not partitions
-- VACUUM FULL ANALYZE bitly_clicks_total; -- Free up used space

-- In case some click counts are to be UPDATEd
DELETE FROM bitly_clicks_total WHERE stories_id IN (
    SELECT stories_id
    FROM temp_bitly_clicks_total_master_table
);

INSERT INTO bitly_clicks_total (stories_id, click_count)
    SELECT DISTINCT stories_id, click_count
    FROM temp_bitly_clicks_total_master_table;

DROP TABLE temp_bitly_clicks_total_master_table;

