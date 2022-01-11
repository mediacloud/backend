package org.mediacloud.mrts.tables;

import java.util.Arrays;

public class SnapStoryLinksWorkflowImpl extends TableMoveWorkflow implements SnapStoryLinksWorkflow {

    @Override
    public void moveSnapStoryLinks() {
        this.moveTable(
                "unsharded_snap.story_links",
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
                                    DELETE FROM unsharded_snap.story_links
                                    USING temp_chunk_timespans
                                    WHERE
                                        unsharded_snap.story_links.timespans_id = temp_chunk_timespans.timespans_id AND
                                        unsharded_snap.story_links.timespans_id BETWEEN %s AND %s
                                    RETURNING
                                        temp_chunk_timespans.topics_id,
                                        unsharded_snap.story_links.timespans_id,
                                        unsharded_snap.story_links.source_stories_id,
                                        unsharded_snap.story_links.ref_stories_id
                                )
                                INSERT INTO sharded_snap.story_links (
                                    topics_id,
                                    timespans_id,
                                    source_stories_id,
                                    ref_stories_id
                                )
                                    SELECT
                                        topics_id::BIGINT,
                                        timespans_id::BIGINT,
                                        source_stories_id::BIGINT,
                                        ref_stories_id::BIGINT
                                    FROM deleted_rows
                                ON CONFLICT (topics_id, timespans_id, source_stories_id, ref_stories_id) DO NOTHING
                                    """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_timespans",
                        "DROP TABLE temp_chunk_timespans"
                )
        );
    }
}
