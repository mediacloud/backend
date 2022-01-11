package org.mediacloud.mrts.tables;

import java.util.List;

public class DownloadTextsPartitionWorkflowImpl extends TableMoveWorkflow implements DownloadTextsPartitionWorkflow {

    @Override
    public void moveDownloadTextsPartition(int partitionIndex) {
        String partitionTable = String.format("unsharded_public.download_texts_%02d", partitionIndex);
        this.moveTable(
                partitionTable,
                "downloads_id",
                // 100,000,000 in source table
                100_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM %s
                            WHERE downloads_id BETWEEN %s and %s
                            RETURNING
                                download_texts_id,
                                downloads_id,
                                download_text,
                                download_text_length
                        )
                        INSERT INTO sharded_public.download_texts (
                            download_texts_id,
                            downloads_id,
                            download_text,
                            download_text_length
                        )
                            SELECT
                                download_texts_id,
                                downloads_id,
                                download_text,
                                download_text_length
                            FROM deleted_rows
                            """, partitionTable, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
