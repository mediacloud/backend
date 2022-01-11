package org.mediacloud.mrts.tables;

import java.util.List;

public class StorySentencesPartitionWorkflowImpl extends TableMoveWorkflow implements StorySentencesPartitionWorkflow {

    @Override
    public void moveStorySentencesPartition(int partitionIndex) {
        String partitionTable = String.format("unsharded_public.story_sentences_p_%02d", partitionIndex);
        this.moveTable(
                partitionTable,
                "stories_id",
                // 100,000,000 in source table
                100_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM %s
                            WHERE stories_id BETWEEN %s and %s
                            RETURNING
                                story_sentences_p_id,
                                stories_id,
                                sentence_number,
                                sentence,
                                media_id,
                                publish_date,
                                language,
                                is_dup
                        )
                        INSERT INTO sharded_public.story_sentences (
                            story_sentences_id,
                            stories_id,
                            sentence_number,
                            sentence,
                            media_id,
                            publish_date,
                            language,
                            is_dup
                        )
                            SELECT
                                story_sentences_p_id::BIGINT AS story_sentences_id,
                                stories_id::BIGINT,
                                sentence_number,
                                sentence,
                                media_id::BIGINT,
                                publish_date,
                                language,
                                is_dup
                            FROM deleted_rows
                            """, partitionTable, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
