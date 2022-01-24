package org.mediacloud.mrts.tables;

import java.util.List;

public class MediaStatsWorkflowImpl extends TableMoveWorkflow implements MediaStatsWorkflow {

    @Override
    public void moveMediaStats() {
        this.moveTable(
                "unsharded_public.media_stats",
                "media_stats_id",
                // 89,970,140 in source table
                100_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.media_stats
                            WHERE media_stats_id BETWEEN %s AND %s
                            RETURNING
                                media_stats_id,
                                media_id,
                                num_stories,
                                num_sentences,
                                stat_date
                        )
                        INSERT INTO sharded_public.media_stats (
                            media_stats_id,
                            media_id,
                            num_stories,
                            num_sentences,
                            stat_date
                        )
                            SELECT
                                media_stats_id::BIGINT,
                                media_id::BIGINT,
                                num_stories::BIGINT,
                                num_sentences::BIGINT,
                                stat_date
                            FROM deleted_rows
                        ON CONFLICT (media_id, stat_date) DO NOTHING
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
