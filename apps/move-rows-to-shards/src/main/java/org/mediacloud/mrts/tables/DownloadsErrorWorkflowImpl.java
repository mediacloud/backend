package org.mediacloud.mrts.tables;

import java.util.List;

public class DownloadsErrorWorkflowImpl extends TableMoveWorkflow implements DownloadsErrorWorkflow {

    @Override
    public void moveDownloadsError() {
        this.moveTable(
                "unsharded_public.downloads_error",
                "downloads_id",
                // 114,330,304 in source table
                200_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.downloads_error
                            WHERE downloads_id BETWEEN %1$s AND %2$s
                            RETURNING %3$s
                        )
                        INSERT INTO sharded_public.downloads_error (%3$s)
                            SELECT %4$s
                            FROM deleted_rows
                            """, START_ID_MARKER, END_ID_MARKER, DOWNLOADS_ID_SRC_COLUMNS, DOWNLOADS_ID_DST_COLUMNS))
        );
    }
}
