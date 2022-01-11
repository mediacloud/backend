package org.mediacloud.mrts.tables;

import java.util.Arrays;

public class SnapMediumLinksWorkflowImpl extends TableMoveWorkflow implements SnapMediumLinksWorkflow {

    @Override
    public void moveSnapMediumLinks() {
        this.moveTable(
                "unsharded_snap.medium_links",
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
                                    DELETE FROM unsharded_snap.medium_links
                                    USING temp_chunk_timespans
                                    WHERE
                                        unsharded_snap.medium_links.timespans_id
                                            = temp_chunk_timespans.timespans_id AND
                                        unsharded_snap.medium_links.timespans_id BETWEEN %s AND %s
                                    RETURNING
                                        temp_chunk_timespans.topics_id,
                                        unsharded_snap.medium_links.timespans_id,
                                        unsharded_snap.medium_links.source_media_id,
                                        unsharded_snap.medium_links.ref_media_id,
                                        unsharded_snap.medium_links.link_count
                                )
                                INSERT INTO sharded_snap.medium_links (
                                    topics_id,
                                    timespans_id,
                                    source_media_id,
                                    ref_media_id,
                                    link_count
                                )
                                    SELECT
                                        topics_id::BIGINT,
                                        timespans_id::BIGINT,
                                        source_media_id::BIGINT,
                                        ref_media_id::BIGINT,
                                        link_count::BIGINT
                                    FROM deleted_rows
                                ON CONFLICT (topics_id, timespans_id, source_media_id, ref_media_id) DO NOTHING
                                    """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_timespans",
                        "DROP TABLE temp_chunk_timespans"
                )
        );
    }
}
