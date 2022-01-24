package org.mediacloud.mrts.tables;

import java.util.List;

public class AuthUserRequestDailyCountsWorkflowImpl extends TableMoveWorkflow implements AuthUserRequestDailyCountsWorkflow {

    @Override
    public void moveAuthUserRequestDailyCounts() {
        this.moveTable(
                "unsharded_public.auth_user_request_daily_counts",
                "auth_user_request_daily_counts_id",
                // 338,454,970 rows in source table
                500_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.auth_user_request_daily_counts
                            WHERE auth_user_request_daily_counts_id BETWEEN %s AND %s
                            RETURNING
                                auth_user_request_daily_counts_id,
                                email,
                                day,
                                requests_count,
                                requested_items_count
                        )
                        INSERT INTO sharded_public.auth_user_request_daily_counts (
                            auth_user_request_daily_counts_id,
                            email,
                            day,
                            requests_count,
                            requested_items_count
                        )
                            SELECT
                                auth_user_request_daily_counts_id::BIGINT,
                                email,
                                day,
                                requests_count::BIGINT,
                                requested_items_count::BIGINT
                            FROM deleted_rows
                        ON CONFLICT (email, day) DO NOTHING
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
