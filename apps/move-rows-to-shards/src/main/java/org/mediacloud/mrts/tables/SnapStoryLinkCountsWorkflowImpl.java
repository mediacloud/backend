package org.mediacloud.mrts.tables;

import java.util.Arrays;

public class SnapStoryLinkCountsWorkflowImpl extends TableMoveWorkflow implements SnapStoryLinkCountsWorkflow {

    @Override
    public void moveSnapStoryLinkCounts() {
        this.moveTable(
                "unsharded_snap.story_link_counts",
                "timespans_id",
                // MAX(timespans_id) = 1_362_209 in source table
                2000,
                Arrays.asList(
                        String.format("""
                                CREATE TEMPORARY TABLE temp_chunk_timespans AS
                                    SELECT
                                        timespans_id::INT,
                                        topics_id::INT
                                    FROM public.timespans
                                    WHERE timespans_id BETWEEN %s AND %s
                                        """, START_ID_MARKER, END_ID_MARKER),
                        String.format("""
                                WITH deleted_rows AS (
                                    DELETE FROM unsharded_snap.story_link_counts
                                    USING temp_chunk_timespans
                                    WHERE
                                        unsharded_snap.story_link_counts.timespans_id = temp_chunk_timespans.timespans_id AND
                                        unsharded_snap.story_link_counts.timespans_id BETWEEN %s AND %s
                                    RETURNING
                                        temp_chunk_timespans.topics_id,
                                        unsharded_snap.story_link_counts.timespans_id,
                                        unsharded_snap.story_link_counts.stories_id,
                                        unsharded_snap.story_link_counts.media_inlink_count,
                                        unsharded_snap.story_link_counts.inlink_count,
                                        unsharded_snap.story_link_counts.outlink_count,
                                        unsharded_snap.story_link_counts.facebook_share_count,
                                        unsharded_snap.story_link_counts.post_count,
                                        unsharded_snap.story_link_counts.author_count,
                                        unsharded_snap.story_link_counts.channel_count
                                )
                                INSERT INTO sharded_snap.story_link_counts (
                                    topics_id,
                                    timespans_id,
                                    stories_id,
                                    media_inlink_count,
                                    inlink_count,
                                    outlink_count,
                                    facebook_share_count,
                                    post_count,
                                    author_count,
                                    channel_count
                                )
                                    SELECT
                                        topics_id::BIGINT,
                                        timespans_id::BIGINT,
                                        stories_id::BIGINT,
                                        media_inlink_count::BIGINT,
                                        inlink_count::BIGINT,
                                        outlink_count::BIGINT,
                                        facebook_share_count::BIGINT,
                                        post_count::BIGINT,
                                        author_count::BIGINT,
                                        channel_count::BIGINT
                                    FROM deleted_rows
                                ON CONFLICT (topics_id, timespans_id, stories_id) DO NOTHING
                                    """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_timespans",
                        "DROP TABLE temp_chunk_timespans"
                )
        );
    }
}
