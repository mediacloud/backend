package org.mediacloud.mrts.tables;

import java.util.List;

public class MediaCoverageGapsWorkflowImpl extends TableMoveWorkflow implements MediaCoverageGapsWorkflow {

    @Override
    public void moveMediaCoverageGaps() {
        this.moveTable(
                "unsharded_public.media_coverage_gaps",
                "media_id",
                // MAX(media_id) = 1,892,933; 63,132,122 rows in source table
                100_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.media_coverage_gaps
                            WHERE media_id BETWEEN %s AND %s
                            RETURNING
                                media_id,
                                stat_week,
                                num_stories,
                                expected_stories,
                                num_sentences,
                                expected_sentences
                        )
                        INSERT INTO sharded_public.media_coverage_gaps (
                            media_id,
                            stat_week,
                            num_stories,
                            expected_stories,
                            num_sentences,
                            expected_sentences
                        )
                            SELECT
                                media_id::BIGINT,
                                stat_week,
                                num_stories,
                                expected_stories,
                                num_sentences,
                                expected_sentences
                            FROM deleted_rows
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
