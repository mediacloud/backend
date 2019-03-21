


DROP TRIGGER stories_tags_map_partition_by_stories_id_insert_trigger ON stories_tags_map;

DROP FUNCTION stories_tags_map_partition_by_stories_id_insert_trigger();


CREATE OR REPLACE FUNCTION stories_tags_map_partition_upsert_trigger() RETURNS TRIGGER AS $$
DECLARE
    target_table_name TEXT;       -- partition table name (e.g. "stories_tags_map_01")
BEGIN
    SELECT stories_partition_name( 'stories_tags_map', NEW.stories_id ) INTO target_table_name;
    EXECUTE '
        INSERT INTO ' || target_table_name || '
            SELECT $1.*
        ON CONFLICT (stories_id, tags_id) DO NOTHING
        ' USING NEW;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER stories_tags_map_partition_upsert_trigger
	BEFORE INSERT ON stories_tags_map
	FOR EACH ROW
	EXECUTE PROCEDURE stories_tags_map_partition_upsert_trigger();




