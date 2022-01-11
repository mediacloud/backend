package org.mediacloud.mrts.tables;

import java.util.List;

public class StoryEnclosuresWorkflowImpl extends TableMoveWorkflow implements StoryEnclosuresWorkflow {

    @Override
    public void moveStoryEnclosures() {
        this.moveTable(
                "unsharded_public.story_enclosures",
                "story_enclosures_id",
                // 153,858,997 in source table
                200_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.story_enclosures
                            WHERE story_enclosures_id BETWEEN %s AND %s
                            RETURNING
                                story_enclosures_id,
                                stories_id,
                                url,
                                mime_type,
                                length
                        )
                        INSERT INTO sharded_public.story_enclosures (
                            story_enclosures_id,
                            stories_id,
                            url,
                            mime_type,
                            length
                        )
                            SELECT
                                story_enclosures_id::BIGINT,
                                stories_id::BIGINT,
                                url,
                                mime_type,
                                length
                            FROM deleted_rows
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
