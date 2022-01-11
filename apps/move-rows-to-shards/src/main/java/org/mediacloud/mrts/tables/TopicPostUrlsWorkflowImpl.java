package org.mediacloud.mrts.tables;

import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Workflow;

import java.util.Arrays;

public class TopicPostUrlsWorkflowImpl extends TableMoveWorkflow implements TopicPostUrlsWorkflow {

    @Override
    public void moveTopicPostUrls() {
        this.moveTable(
                "unsharded_public.topic_post_urls",
                "topic_post_urls_id",
                // 50,726,436 in source table
                100_000,
                Arrays.asList(
                        // Citus doesn't like it when we join local (unsharded) and distributed tables in this case
                        // therefore we create a temporary table first
                        String.format("""
                                CREATE TEMPORARY TABLE temp_chunk_topic_posts AS
                                    SELECT
                                        topic_posts_id::INT,
                                        topics_id::INT
                                    FROM sharded_public.topic_posts
                                    WHERE topic_posts_id IN (
                                        SELECT topic_posts_id
                                        FROM unsharded_public.topic_post_urls
                                        WHERE topic_post_urls_id BETWEEN %s AND %s
                                    )
                                """, START_ID_MARKER, END_ID_MARKER),
                        String.format("""
                                WITH deleted_rows AS (
                                    DELETE FROM unsharded_public.topic_post_urls
                                    USING temp_chunk_topic_posts
                                    WHERE
                                        unsharded_public.topic_post_urls.topic_posts_id
                                            = temp_chunk_topic_posts.topic_posts_id AND
                                        unsharded_public.topic_post_urls.topic_post_urls_id BETWEEN %s AND %s
                                    RETURNING
                                        unsharded_public.topic_post_urls.topic_post_urls_id,
                                        temp_chunk_topic_posts.topics_id,
                                        unsharded_public.topic_post_urls.topic_posts_id,
                                        unsharded_public.topic_post_urls.url
                                )
                                INSERT INTO sharded_public.topic_post_urls (
                                    topic_post_urls_id,
                                    topics_id,
                                    topic_posts_id,
                                    url
                                )
                                    SELECT
                                        topic_post_urls_id::BIGINT,
                                        topics_id,
                                        topic_posts_id::BIGINT,
                                        url::TEXT
                                    FROM deleted_rows
                                """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_topic_posts",
                        "DROP TABLE temp_chunk_topic_posts"
                )
        );

        // Move tables that depend on "topic_post_urls"
        Workflow.newChildWorkflowStub(
                TopicSeedUrlsWorkflow.class,
                ChildWorkflowOptions.newBuilder()
                        .setWorkflowId("topic_seed_urls")
                        .build()
        ).moveTopicSeedUrls();
    }
}
