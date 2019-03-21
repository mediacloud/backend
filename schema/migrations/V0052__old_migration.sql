


DROP FUNCTION copy_chunk_of_nonpartitioned_sentences_to_partitions(story_chunk_size INT);

-- Copy a chunk of story sentences from a non-partitioned "story_sentences" to a
-- partitioned one:
--
-- * Expects starting and ending stories_id instead of a chunk size in order to
--   avoid index bloat that would happen when copying sentences in sequential
--   chunks
-- * Copies directly to partitions to skip (slow) INSERT triggers on
--   "story_sentences" view
-- * Disables all triggers while copying to skip updating db_row_last_updated
--
-- Returns number of rows that were copied.
--
-- Call this repeatedly to migrate all the data to the partitioned table.
CREATE OR REPLACE FUNCTION copy_chunk_of_nonpartitioned_sentences_to_partitions(start_stories_id INT, end_stories_id INT)
RETURNS INT AS $$

DECLARE
    copied_sentence_count INT;

    -- Partition table names for both stories_id bounds
    start_stories_id_table_name TEXT;
    end_stories_id_table_name TEXT;

BEGIN

    IF NOT (start_stories_id < end_stories_id) THEN
        RAISE EXCEPTION '"end_stories_id" must be bigger than "start_stories_id".';
    END IF;

    SELECT stories_partition_name('story_sentences_partitioned', start_stories_id)
        INTO start_stories_id_table_name;
    IF NOT (table_exists(start_stories_id_table_name)) THEN
        RAISE EXCEPTION
            'Table "%" for "start_stories_id" = % does not exist.',
            start_stories_id_table_name, start_stories_id;
    END IF;

    SELECT stories_partition_name('story_sentences_partitioned', end_stories_id)
        INTO end_stories_id_table_name;
    IF NOT (table_exists(end_stories_id_table_name)) THEN
        RAISE EXCEPTION
            'Table "%" for "end_stories_id" = % does not exist.',
            end_stories_id_table_name, end_stories_id;
    END IF;

    IF NOT (start_stories_id_table_name = end_stories_id_table_name) THEN
        RAISE EXCEPTION
            '"start_stories_id" = % and "end_stories_id" = % must be within the same partition.',
            start_stories_id, end_stories_id;
    END IF;

    -- Kill all autovacuums before proceeding with DDL changes
    PERFORM pid
    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
    WHERE backend_type = 'autovacuum worker'
      AND query ~ 'story_sentences';

    RAISE NOTICE
        'Copying sentences of stories_id BETWEEN % AND % to the partitioned table...',
        start_stories_id, end_stories_id;

    -- Disable all triggers to avoid hitting last_updated_trigger() -- the
    -- copied rows don't need their db_row_last_updated to be updated
    SET session_replication_role = REPLICA;

    BEGIN

        EXECUTE '

            -- Fetch and delete sentences within bounds
            WITH deleted_rows AS (
                DELETE FROM story_sentences_nonpartitioned
                WHERE stories_id BETWEEN ' || start_stories_id || ' AND ' || end_stories_id || '
                RETURNING story_sentences_nonpartitioned.*
            ),

            -- Deduplicate sentences: nonpartitioned table has weird duplicates,
            -- and the new index insists on (stories_id, sentence_number)
            -- uniqueness (which is a logical assumption to make)
            --
            -- Assume that the sentence with the biggest story_sentences_id is the
            -- newest one and so is the one that we want.
            deduplicated_rows AS (
                SELECT DISTINCT ON (stories_id, sentence_number) *
                FROM deleted_rows
                ORDER BY stories_id, sentence_number, story_sentences_nonpartitioned_id DESC
            )

            -- INSERT directly into the partition to circumvent slow insertion
            -- trigger on "story_sentences" view
            INSERT INTO ' || start_stories_id_table_name || ' (
                story_sentences_partitioned_id,
                stories_id,
                sentence_number,
                sentence,
                media_id,
                publish_date,
                db_row_last_updated,
                language,
                is_dup
            )
            SELECT
                story_sentences_nonpartitioned_id,
                stories_id,
                sentence_number,
                sentence,
                media_id,
                publish_date,
                db_row_last_updated,
                language,
                is_dup
            FROM deduplicated_rows;

        ';

        GET DIAGNOSTICS copied_sentence_count = ROW_COUNT;

    EXCEPTION WHEN others THEN

        -- Reenable all triggers
        SET session_replication_role = DEFAULT;

        RAISE EXCEPTION '% %', SQLERRM, SQLSTATE;

    END;

    -- Reenable all triggers
    SET session_replication_role = DEFAULT;

    RAISE NOTICE
        'Finished copying sentences of stories_id BETWEEN % AND % to the partitioned table, copied % sentences.',
        start_stories_id, end_stories_id, copied_sentence_count;

    RETURN copied_sentence_count;

END;
$$
LANGUAGE plpgsql;



