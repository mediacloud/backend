package org.mediacloud.mrts.tables;

import java.util.List;

public class SnapLiveStoriesWorkflowImpl extends TableMoveWorkflow implements SnapLiveStoriesWorkflow {

    @Override
    public void moveSnapLiveStories() {
        this.moveTable(
                "unsharded_snap.live_stories",
                "topic_stories_id",
                // MAX(topic_stories_id) = 165_082_931 in source table
                200_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_snap.live_stories
                            WHERE topic_stories_id BETWEEN %s AND %s
                            RETURNING
                                topics_id,
                                topic_stories_id,
                                stories_id,
                                media_id,
                                url,
                                guid,
                                title,
                                normalized_title_hash,
                                description,
                                publish_date,
                                collect_date,
                                full_text_rss,
                                language
                        )
                        INSERT INTO sharded_snap.live_stories (
                            topics_id,
                            topic_stories_id,
                            stories_id,
                            media_id,
                            url,
                            guid,
                            title,
                            normalized_title_hash,
                            description,
                            publish_date,
                            collect_date,
                            full_text_rss,
                            language
                        )
                            SELECT
                                topics_id::BIGINT,
                                topic_stories_id::BIGINT,
                                stories_id::BIGINT,
                                media_id::BIGINT,
                                url::TEXT,
                                guid::TEXT,
                                title,
                                normalized_title_hash,
                                description,
                                publish_date,
                                collect_date,
                                full_text_rss,
                                language
                            FROM deleted_rows
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
