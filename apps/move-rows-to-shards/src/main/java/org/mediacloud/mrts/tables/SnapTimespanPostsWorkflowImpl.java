package org.mediacloud.mrts.tables;

import java.util.Arrays;

public class SnapTimespanPostsWorkflowImpl extends TableMoveWorkflow implements SnapTimespanPostsWorkflow {

    @Override
    public void moveSnapTimespanPosts() {
        this.moveTable(
                "unsharded_snap.timespan_posts",
                "timespans_id",
                // MAX(timespans_id) = 1_362_209 in source table
                2000,
                Arrays.asList(
                        // Citus doesn't like it when we join local (unsharded) and distributed tables in this case
                        // therefore we create a temporary table first
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
                                    DELETE FROM unsharded_snap.timespan_posts
                                    USING temp_chunk_timespans
                                    WHERE
                                        unsharded_snap.timespan_posts.timespans_id
                                            = temp_chunk_timespans.timespans_id AND
                                        unsharded_snap.timespan_posts.timespans_id BETWEEN %s AND %s
                                    RETURNING
                                        temp_chunk_timespans.topics_id,
                                        unsharded_snap.timespan_posts.timespans_id,
                                        unsharded_snap.timespan_posts.topic_posts_id
                                )
                                INSERT INTO sharded_snap.timespan_posts (
                                    topics_id,
                                    timespans_id,
                                    topic_posts_id
                                )
                                    SELECT
                                        topics_id::BIGINT,
                                        timespans_id::BIGINT,
                                        topic_posts_id::BIGINT
                                    FROM deleted_rows
                                    """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_timespans",
                        "DROP TABLE temp_chunk_timespans"
                )
        );
    }
}
