package org.mediacloud.mrts.tables;

import java.util.List;

public class SnapTopicLinksCrossMediaWorkflowImpl extends TableMoveWorkflow implements SnapTopicLinksCrossMediaWorkflow {

    @Override
    public void moveSnapTopicLinksCrossMedia() {
        this.moveTable(
                "unsharded_snap.topic_links_cross_media",
                "snapshots_id",
                // MAX(snapshots_id) = 7690 in source table
                10,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_snap.topic_links_cross_media
                            WHERE snapshots_id BETWEEN %s AND %s
                            RETURNING
                                topics_id,
                                snapshots_id,
                                topic_links_id,
                                stories_id,
                                url,
                                ref_stories_id
                        )
                        INSERT INTO sharded_snap.topic_links_cross_media (
                            topics_id,
                            snapshots_id,
                            topic_links_id,
                            stories_id,
                            url,
                            ref_stories_id
                        )
                            SELECT
                                topics_id::BIGINT,
                                snapshots_id::BIGINT,
                                topic_links_id::BIGINT,
                                stories_id::BIGINT,
                                url,
                                ref_stories_id::BIGINT
                            FROM deleted_rows
                        ON CONFLICT (topics_id, snapshots_id, stories_id, ref_stories_id) DO NOTHING
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
