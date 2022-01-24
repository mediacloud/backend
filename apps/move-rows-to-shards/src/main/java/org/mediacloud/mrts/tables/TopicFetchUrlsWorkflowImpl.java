package org.mediacloud.mrts.tables;

import java.util.List;

public class TopicFetchUrlsWorkflowImpl extends TableMoveWorkflow implements TopicFetchUrlsWorkflow {

    @Override
    public void moveTopicFetchUrls() {
        this.moveTable(
                "unsharded_public.topic_fetch_urls",
                "topic_fetch_urls_id",
                // 705,821,290 in source table
                1_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.topic_fetch_urls
                            WHERE topic_fetch_urls_id BETWEEN %s AND %s
                            RETURNING
                                topic_fetch_urls_id,
                                topics_id,
                                url,
                                code,
                                fetch_date,
                                state,
                                message,
                                stories_id,
                                assume_match,
                                topic_links_id
                        )
                        INSERT INTO sharded_public.topic_fetch_urls (
                            topic_fetch_urls_id,
                            topics_id,
                            url,
                            code,
                            fetch_date,
                            state,
                            message,
                            stories_id,
                            assume_match,
                            topic_links_id
                        )
                            SELECT
                                topic_fetch_urls_id::BIGINT,
                                topics_id::BIGINT,
                                url,
                                code,
                                fetch_date,
                                state,
                                message,
                                stories_id::BIGINT,
                                assume_match,
                                topic_links_id::BIGINT
                            FROM deleted_rows
                            """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
