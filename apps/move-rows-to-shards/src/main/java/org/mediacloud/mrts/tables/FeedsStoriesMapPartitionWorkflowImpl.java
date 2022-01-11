package org.mediacloud.mrts.tables;

import java.util.List;

public class FeedsStoriesMapPartitionWorkflowImpl extends TableMoveWorkflow implements FeedsStoriesMapPartitionWorkflow {

    @Override
    public void moveFeedsStoriesMapPartition(int partitionIndex) {
        String partitionTable = String.format("unsharded_public.feeds_stories_map_p_%02d", partitionIndex);
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
                                feeds_stories_map_p_id,
                                feeds_id,
                                stories_id
                        )
                        INSERT INTO sharded_public.feeds_stories_map (
                            feeds_stories_map_id,
                            feeds_id,
                            stories_id
                        )
                            SELECT
                                feeds_stories_map_p_id::BIGINT AS feeds_stories_map_id,
                                feeds_id::BIGINT,
                                stories_id::BIGINT
                            FROM deleted_rows
                            """, partitionTable, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
