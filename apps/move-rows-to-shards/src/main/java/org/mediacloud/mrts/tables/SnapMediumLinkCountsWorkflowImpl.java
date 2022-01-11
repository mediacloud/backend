package org.mediacloud.mrts.tables;

import java.util.Arrays;

public class SnapMediumLinkCountsWorkflowImpl extends TableMoveWorkflow implements SnapMediumLinkCountsWorkflow {

    @Override
    public void moveSnapMediumLinkCounts() {
        this.moveTable(
                "unsharded_snap.medium_link_counts",
                "timespans_id",
                // MAX(timespans_id) = 1_362_209 in source table
                2000,
                // Citus doesn't like it when we join local (unsharded) and distributed tables in this case therefore we
                // create a temporary table first
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
                                    DELETE FROM unsharded_snap.medium_link_counts
                                    USING temp_chunk_timespans
                                    WHERE
                                        unsharded_snap.medium_link_counts.timespans_id = temp_chunk_timespans.timespans_id AND
                                        unsharded_snap.medium_link_counts.timespans_id BETWEEN %s AND %s
                                    RETURNING
                                        temp_chunk_timespans.topics_id,
                                        unsharded_snap.medium_link_counts.timespans_id,
                                        unsharded_snap.medium_link_counts.media_id,
                                        unsharded_snap.medium_link_counts.sum_media_inlink_count,
                                        unsharded_snap.medium_link_counts.media_inlink_count,
                                        unsharded_snap.medium_link_counts.inlink_count,
                                        unsharded_snap.medium_link_counts.outlink_count,
                                        unsharded_snap.medium_link_counts.story_count,
                                        unsharded_snap.medium_link_counts.facebook_share_count,
                                        unsharded_snap.medium_link_counts.sum_post_count,
                                        unsharded_snap.medium_link_counts.sum_author_count,
                                        unsharded_snap.medium_link_counts.sum_channel_count
                                )
                                INSERT INTO sharded_snap.medium_link_counts (
                                    topics_id,
                                    timespans_id,
                                    media_id,
                                    sum_media_inlink_count,
                                    media_inlink_count,
                                    inlink_count,
                                    outlink_count,
                                    story_count,
                                    facebook_share_count,
                                    sum_post_count,
                                    sum_author_count,
                                    sum_channel_count
                                )
                                    SELECT
                                        topics_id::BIGINT,
                                        timespans_id::BIGINT,
                                        media_id::BIGINT,
                                        sum_media_inlink_count::BIGINT,
                                        media_inlink_count::BIGINT,
                                        inlink_count::BIGINT,
                                        outlink_count::BIGINT,
                                        story_count::BIGINT,
                                        facebook_share_count::BIGINT,
                                        sum_post_count::BIGINT,
                                        sum_author_count::BIGINT,
                                        sum_channel_count::BIGINT
                                    FROM deleted_rows
                                ON CONFLICT (topics_id, timespans_id, media_id) DO NOTHING
                                    """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_timespans",
                        "DROP TABLE temp_chunk_timespans"
                )
        );
    }
}
