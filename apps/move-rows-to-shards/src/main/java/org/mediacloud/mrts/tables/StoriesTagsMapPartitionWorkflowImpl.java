package org.mediacloud.mrts.tables;

import java.util.List;

public class StoriesTagsMapPartitionWorkflowImpl extends TableMoveWorkflow implements StoriesTagsMapPartitionWorkflow {

    @Override
    public void moveStoriesTagsMapPartition(int partitionIndex) {
        String partitionTable = String.format("unsharded_public.stories_tags_map_p_%02d", partitionIndex);
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
                                stories_tags_map_p_id,
                                stories_id,
                                tags_id
                        )
                        INSERT INTO sharded_public.stories_tags_map (
                            stories_tags_map_id,
                            stories_id,
                            tags_id
                        )
                            SELECT
                                stories_tags_map_p_id::BIGINT AS stories_tags_map_id,
                                stories_id::BIGINT,
                                tags_id::BIGINT
                            FROM deleted_rows
                        """, partitionTable, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
