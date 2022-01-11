package org.mediacloud.mrts.tables;

import java.util.List;

public class StoryUrlsWorkflowImpl extends TableMoveWorkflow implements StoryUrlsWorkflow {

    @Override
    public void moveStoryUrls() {
        this.moveTable(
                "unsharded_public.story_urls",
                "story_urls_id",
                // 2,223,082,697 in source table
                3_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.story_urls
                            WHERE story_urls_id BETWEEN %s and %s
                            RETURNING
                                story_urls_id,
                                stories_id,
                                url
                        )
                        INSERT INTO sharded_public.story_urls (
                            story_urls_id,
                            stories_id,
                            url
                        )
                            SELECT
                                story_urls_id::BIGINT,
                                stories_id::BIGINT,
                                url::TEXT
                            FROM deleted_rows
                        ON CONFLICT (url, stories_id) DO NOTHING
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
