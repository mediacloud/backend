package org.mediacloud.mrts.tables;

import java.util.Arrays;

public class SnapMediaTagsMapWorkflowImpl extends TableMoveWorkflow implements SnapMediaTagsMapWorkflow {

    @Override
    public void moveSnapMediaTagsMap() {
        this.moveTable(
                "unsharded_snap.media_tags_map",
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
                                    DELETE FROM unsharded_snap.media_tags_map
                                    USING temp_chunk_snapshots
                                    WHERE
                                        unsharded_snap.media_tags_map.snapshots_id = temp_chunk_snapshots.snapshots_id AND
                                        unsharded_snap.media_tags_map.snapshots_id BETWEEN %s AND %s
                                    RETURNING
                                        temp_chunk_snapshots.topics_id,
                                        unsharded_snap.media_tags_map.snapshots_id,
                                        unsharded_snap.media_tags_map.media_tags_map_id,
                                        unsharded_snap.media_tags_map.media_id,
                                        unsharded_snap.media_tags_map.tags_id
                                )
                                INSERT INTO sharded_snap.media_tags_map (
                                    topics_id,
                                    snapshots_id,
                                    media_tags_map_id,
                                    media_id,
                                    tags_id
                                )
                                    SELECT
                                        topics_id::BIGINT,
                                        snapshots_id::BIGINT,
                                        media_tags_map_id::BIGINT,
                                        media_id::BIGINT,
                                        tags_id::BIGINT
                                    FROM deleted_rows
                                ON CONFLICT (topics_id, snapshots_id, media_id, tags_id) DO NOTHING
                                    """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_snapshots",
                        "DROP TABLE temp_chunk_snapshots"
                )
        );
    }
}
