package org.mediacloud.mrts.tables;

import java.util.List;

public class StoriesApSyndicatedWorkflowImpl extends TableMoveWorkflow implements StoriesApSyndicatedWorkflow {

    @Override
    public void moveStoriesApSyndicated() {
        this.moveTable(
                "unsharded_public.stories_ap_syndicated",
                "stories_ap_syndicated_id",
                // 1,715,725,719 in source table
                2_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.stories_ap_syndicated
                            WHERE stories_ap_syndicated_id BETWEEN %s AND %s
                            RETURNING
                                stories_ap_syndicated_id,
                                stories_id,
                                ap_syndicated
                        )
                        INSERT INTO sharded_public.stories_ap_syndicated (
                            stories_ap_syndicated_id,
                            stories_id,
                            ap_syndicated
                        )
                            SELECT
                                stories_ap_syndicated_id::BIGINT,
                                stories_id::BIGINT,
                                ap_syndicated
                            FROM deleted_rows
                        ON CONFLICT (stories_id) DO NOTHING
                        """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
