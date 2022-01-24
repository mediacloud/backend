package org.mediacloud.mrts.tables;

import java.util.List;

public class ProcessedStoriesWorkflowImpl extends TableMoveWorkflow implements ProcessedStoriesWorkflow {

    @Override
    public void moveProcessedStories() {
        this.moveTable(
                "unsharded_public.processed_stories",
                "processed_stories_id",
                // 2,518,182,153 in source table
                5_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.processed_stories
                            WHERE processed_stories_id BETWEEN %s AND %s
                            RETURNING
                                processed_stories_id,
                                stories_id
                        )
                        INSERT INTO sharded_public.processed_stories (
                            processed_stories_id,
                            stories_id
                        )
                            SELECT
                                processed_stories_id::BIGINT,
                                stories_id::BIGINT
                            FROM deleted_rows
                        ON CONFLICT (stories_id) DO NOTHING
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
