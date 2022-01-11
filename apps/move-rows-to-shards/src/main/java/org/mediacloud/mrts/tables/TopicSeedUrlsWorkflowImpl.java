package org.mediacloud.mrts.tables;

import java.util.List;

public class TopicSeedUrlsWorkflowImpl extends TableMoveWorkflow implements TopicSeedUrlsWorkflow {

    @Override
    public void moveTopicSeedUrls() {
        this.moveTable(
                "unsharded_public.topic_seed_urls",
                "topic_seed_urls_id",
                // 499,926,808 in source table
                500_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.topic_seed_urls
                            WHERE topic_seed_urls_id BETWEEN %s AND %s
                            RETURNING
                                topic_seed_urls_id,
                                topics_id,
                                url,
                                source,
                                stories_id,
                                processed,
                                assume_match,
                                content,
                                guid,
                                title,
                                publish_date,
                                topic_seed_queries_id,
                                topic_post_urls_id
                        )
                        INSERT INTO sharded_public.topic_seed_urls (
                            topic_seed_urls_id,
                            topics_id,
                            url,
                            source,
                            stories_id,
                            processed,
                            assume_match,
                            content,
                            guid,
                            title,
                            publish_date,
                            topic_seed_queries_id,
                            topic_post_urls_id
                        )
                            SELECT
                                topic_seed_urls_id::BIGINT,
                                topics_id::BIGINT,
                                url,
                                source,
                                stories_id::BIGINT,
                                processed,
                                assume_match,
                                content,
                                guid,
                                title,
                                publish_date,
                                topic_seed_queries_id::BIGINT,
                                topic_post_urls_id::BIGINT
                            FROM deleted_rows
                        """, START_ID_MARKER, END_ID_MARKER))
        );
    }
}
