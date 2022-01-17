CREATE FUNCTION public.drop_if_table_is_not_empty(table_name TEXT) RETURNS VOID AS
$$
DECLARE
    table_has_rows BIGINT;
BEGIN
    IF NOT EXISTS(SELECT 1 WHERE table_name ILIKE 'unsharded_%') THEN
        RAISE EXCEPTION 'Table name "%s" should start with "unsharded_".', table_name;
    END IF;
    EXECUTE 'SELECT 1 WHERE EXISTS (SELECT 1 FROM ' || quote_ident(table_name) || ') ' INTO table_has_rows;
    IF table_has_rows THEN
        RAISE EXCEPTION 'Table "%s" is not empty.', table_name;
    END IF;
    EXECUTE 'DROP TABLE ' + table_name;
END;
$$ LANGUAGE plpgsql;


-- Drop partitions first
DO
$$
    DECLARE

        tables CURSOR FOR
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'unsharded_public'
              AND (
                        tablename LIKE 'download_texts_%' OR
                        tablename LIKE 'downloads_success_content_%' OR
                        tablename LIKE 'downloads_success_feed_%' OR
                        tablename LIKE 'feeds_stories_map_p_%' OR
                        tablename LIKE 'stories_tags_map_p_%' OR
                        tablename LIKE 'story_sentences_p_%'
                )
            ORDER BY
                -- First drop "download_texts", then "downloads_" partitions
                tablename LIKE 'download_texts_%' DESC,
                tablename
        ;

    BEGIN
        FOR table_record IN tables
            LOOP
                PERFORM public.drop_if_table_is_not_empty('unsharded_public.' || table_record.tablename);
            END LOOP;
    END
$$;



DROP FUNCTION public.drop_if_table_is_not_empty(TEXT);
