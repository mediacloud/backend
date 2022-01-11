package org.mediacloud.mrts.tables;

import java.util.List;

public class StoryStatisticsWorkflowImpl extends TableMoveWorkflow implements StoryStatisticsWorkflow {

    @Override
    public void moveStoryStatistics() {
        this.moveTable(
                "unsharded_public.story_statistics",
                "story_statistics_id",
                // Rather small table
                100_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.story_statistics
                            WHERE story_statistics_id BETWEEN %s AND %s
                            RETURNING
                                story_statistics_id,
                                stories_id,
                                facebook_share_count,
                                facebook_comment_count,
                                facebook_reaction_count,
                                facebook_api_collect_date,
                                facebook_api_error
                        )
                        INSERT INTO sharded_public.story_statistics (
                            story_statistics_id,
                            stories_id,
                            facebook_share_count,
                            facebook_comment_count,
                            facebook_reaction_count,
                            facebook_api_collect_date,
                            facebook_api_error
                        )
                            SELECT
                                story_statistics_id::BIGINT,
                                stories_id::BIGINT,
                                facebook_share_count::BIGINT,
                                facebook_comment_count::BIGINT,
                                facebook_reaction_count::BIGINT,
                                facebook_api_collect_date,
                                facebook_api_error
                            FROM deleted_rows
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
