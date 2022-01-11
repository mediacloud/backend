package org.mediacloud.mrts.tables;

import java.util.List;

public class DownloadsSuccessFeedPartitionWorkflowImpl extends TableMoveWorkflow implements DownloadsSuccessFeedPartitionWorkflow {

    @Override
    public void moveDownloadsSuccessFeedPartition(int partitionIndex) {
        String partitionTable = String.format("unsharded_public.downloads_success_feed_%02d", partitionIndex);
        this.moveTable(
                partitionTable,
                "downloads_id",
                // 100,000,000 in source table
                100_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM %1$s
                            WHERE downloads_id BETWEEN %2$s and %3$s
                            RETURNING %4$s
                        )
                        INSERT INTO sharded_public.downloads_success (%4$s)
                            SELECT %5$s
                            FROM deleted_rows
                            """, partitionTable, START_ID_MARKER, END_ID_MARKER, DOWNLOADS_ID_SRC_COLUMNS, DOWNLOADS_ID_DST_COLUMNS))
        );
    }
}
