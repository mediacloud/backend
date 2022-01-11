package org.mediacloud.mrts.tables;

import java.util.List;

public class SnapTopicStoriesWorkflowImpl extends TableMoveWorkflow implements SnapTopicStoriesWorkflow {

    @Override
    public void moveSnapTopicStories() {
        this.moveTable(
                "unsharded_snap.topic_stories",
                "snapshots_id",
                // MAX(snapshots_id) = 7690 in source table
                10,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_snap.topic_stories
                            WHERE snapshots_id BETWEEN %s AND %s
                            RETURNING
                                topics_id,
                                snapshots_id,
                                topic_stories_id,
                                stories_id,
                                link_mined,
                                iteration,
                                link_weight,
                                redirect_url,
                                valid_foreign_rss_story
                        )
                        INSERT INTO sharded_snap.topic_stories (
                            topics_id,
                            snapshots_id,
                            topic_stories_id,
                            stories_id,
                            link_mined,
                            iteration,
                            link_weight,
                            redirect_url,
                            valid_foreign_rss_story
                        )
                            SELECT
                                topics_id::BIGINT,
                                snapshots_id::BIGINT,
                                topic_stories_id::BIGINT,
                                stories_id::BIGINT,
                                link_mined,
                                iteration::BIGINT,
                                link_weight,
                                redirect_url,
                                valid_foreign_rss_story
                            FROM deleted_rows
                        ON CONFLICT (topics_id, snapshots_id, stories_id) DO NOTHING
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
