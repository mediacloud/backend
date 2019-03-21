-- Copy a chunk of story sentences from a non-partitioned "story_sentences" to a
-- partitioned one; call this repeatedly to migrate all the data to the partitioned table
CREATE OR REPLACE FUNCTION copy_chunk_of_nonpartitioned_sentences_to_partitions(story_chunk_size INT)
RETURNS VOID AS $$
BEGIN


    RAISE NOTICE 'Copying sentences of up to % stories to the partitioned table...', story_chunk_size;

    -- Kill all autovacuums before proceeding with DDL changes
    PERFORM pid
    FROM pg_stat_activity, LATERAL pg_cancel_backend(pid) f
    WHERE backend_type = 'autovacuum worker'
      AND query ~ 'story_sentences';

    WITH deleted_rows AS (

        -- Fetch and delete sentences of selected stories
        DELETE FROM story_sentences_nonpartitioned
        WHERE stories_id IN (

            -- Start with fetching a bunch of stories to copy between tables to
            -- ensure that all of every story's sentences get copied in a single
            -- chunk so that they could get deduplicated
            SELECT stories_id
            FROM story_sentences_nonpartitioned

            -- Follow the insertion order to copy to the oldest (and less busy)
            -- partitions first
            ORDER BY stories_id

            LIMIT story_chunk_size

        )
        RETURNING story_sentences_nonpartitioned.*

    ),

    deduplicated_rows AS (

        -- Deduplicate sentences (nonpartitioned table has weird duplicates)
        SELECT DISTINCT ON (stories_id, sentence_number) *
        FROM deleted_rows

        -- Assume that the sentence with the biggest story_sentences_id is the
        -- newest one and so is the one that we want
        ORDER BY stories_id, sentence_number, story_sentences_nonpartitioned_id DESC

    )

    -- INSERT into view to hit the partitioning trigger
    INSERT INTO story_sentences (
        story_sentences_id,
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

    RAISE NOTICE 'Done copying sentences of up to % stories to the partitioned table.', story_chunk_size;

END;
$$
LANGUAGE plpgsql;



