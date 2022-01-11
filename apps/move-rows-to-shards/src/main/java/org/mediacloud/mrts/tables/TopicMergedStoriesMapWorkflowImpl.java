package org.mediacloud.mrts.tables;

import java.util.List;

public class TopicMergedStoriesMapWorkflowImpl extends TableMoveWorkflow implements TopicMergedStoriesMapWorkflow {

    @Override
    public void moveTopicMergedStoriesMap() {
        this.moveTable(
                "unsharded_public.topic_merged_stories_map",
                "source_stories_id",
                // Rather small table
                100_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.topic_merged_stories_map
                            WHERE source_stories_id BETWEEN %s AND %s
                            RETURNING
                                source_stories_id,
                                target_stories_id
                        )
                        INSERT INTO sharded_public.topic_merged_stories_map (
                            source_stories_id,
                            target_stories_id
                        )
                            SELECT
                                source_stories_id::BIGINT,
                                target_stories_id::BIGINT
                            FROM deleted_rows
                        ON CONFLICT (source_stories_id, target_stories_id) DO NOTHING
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
