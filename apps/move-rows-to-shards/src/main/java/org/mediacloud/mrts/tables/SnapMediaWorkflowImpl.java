package org.mediacloud.mrts.tables;

import java.util.Arrays;

public class SnapMediaWorkflowImpl extends TableMoveWorkflow implements SnapMediaWorkflow {

    @Override
    public void moveSnapMedia() {
        this.moveTable(
                "unsharded_snap.media",
                "snapshots_id",
                // MAX(snapshots_id) = 7690 in source table
                10,
                Arrays.asList(
                        // Citus doesn't like it when we join local (unsharded) and distributed tables in this case
                        // therefore we create a temporary table first
                        String.format("""
                                CREATE TEMPORARY TABLE temp_chunk_snapshots AS
                                    SELECT
                                        snapshots_id::INT,
                                        topics_id::INT
                                    FROM public.snapshots
                                    WHERE snapshots_id BETWEEN %s AND %s
                                    """, START_ID_MARKER, END_ID_MARKER),
                        String.format("""
                                WITH deleted_rows AS (
                                    DELETE FROM unsharded_snap.media
                                    USING temp_chunk_snapshots
                                    WHERE
                                        unsharded_snap.media.snapshots_id = temp_chunk_snapshots.snapshots_id AND
                                        unsharded_snap.media.snapshots_id BETWEEN %s AND %s
                                    RETURNING
                                        temp_chunk_snapshots.topics_id,
                                        unsharded_snap.media.snapshots_id,
                                        unsharded_snap.media.media_id,
                                        unsharded_snap.media.url,
                                        unsharded_snap.media.name,
                                        unsharded_snap.media.full_text_rss,
                                        unsharded_snap.media.foreign_rss_links,
                                        unsharded_snap.media.dup_media_id,
                                        unsharded_snap.media.is_not_dup
                                )
                                INSERT INTO sharded_snap.media (
                                    topics_id,
                                    snapshots_id,
                                    media_id,
                                    url,
                                    name,
                                    full_text_rss,
                                    foreign_rss_links,
                                    dup_media_id,
                                    is_not_dup
                                )
                                    SELECT
                                        topics_id::BIGINT,
                                        snapshots_id::BIGINT,
                                        media_id::BIGINT,
                                        url::TEXT,
                                        name::TEXT,
                                        full_text_rss,
                                        foreign_rss_links,
                                        dup_media_id::BIGINT,
                                        is_not_dup
                                    FROM deleted_rows
                                ON CONFLICT (topics_id, snapshots_id, media_id) DO NOTHING
                                            """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_snapshots",
                        "DROP TABLE temp_chunk_snapshots"
                )
        );
    }
}
