package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.Arrays;

public class TopicPostsWorkflowImpl extends TableMoveWorkflow implements TopicPostsWorkflow {

    @Override
    public void moveTopicPosts() {
        this.moveTable(
                "unsharded_public.topic_posts",
                "topic_posts_id",
                // 95,486,494 in source table
                100_000,
                Arrays.asList(
                        // Citus doesn't like it when we join local (unsharded) and distributed tables in this case
                        // therefore we create a temporary table first
                        String.format("""
                                CREATE TEMPORARY TABLE temp_chunk_topic_post_days AS
                                    SELECT
                                        topic_post_days_id::INT,
                                        topics_id::INT
                                    FROM public.topic_post_days
                                    WHERE topic_post_days_id IN (
                                        SELECT topic_post_days_id
                                        FROM unsharded_public.topic_posts
                                        WHERE topic_posts_id BETWEEN %s AND %s
                                    )
                                        """, START_ID_MARKER, END_ID_MARKER),
                        String.format("""
                                WITH deleted_rows AS (
                                    DELETE FROM unsharded_public.topic_posts
                                    USING temp_chunk_topic_post_days
                                    WHERE
                                        unsharded_public.topic_posts.topic_post_days_id
                                            = temp_chunk_topic_post_days.topic_post_days_id AND
                                        unsharded_public.topic_posts.topic_posts_id BETWEEN %s AND %s
                                    RETURNING
                                        unsharded_public.topic_posts.topic_posts_id,
                                        temp_chunk_topic_post_days.topics_id,
                                        unsharded_public.topic_posts.topic_post_days_id,
                                        unsharded_public.topic_posts.data,
                                        unsharded_public.topic_posts.post_id,
                                        unsharded_public.topic_posts.content,
                                        unsharded_public.topic_posts.publish_date,
                                        unsharded_public.topic_posts.author,
                                        unsharded_public.topic_posts.channel,
                                        unsharded_public.topic_posts.url
                                )
                                INSERT INTO sharded_public.topic_posts (
                                    topic_posts_id,
                                    topics_id,
                                    topic_post_days_id,
                                    data,
                                    post_id,
                                    content,
                                    publish_date,
                                    author,
                                    channel,
                                    url
                                )
                                    SELECT
                                        topic_posts_id::BIGINT,
                                        topics_id::BIGINT,
                                        topic_post_days_id::BIGINT,
                                        data,
                                        post_id::TEXT,
                                        content,
                                        publish_date,
                                        author::TEXT,
                                        channel::TEXT,
                                        url
                                    FROM deleted_rows
                                            """, START_ID_MARKER, END_ID_MARKER),
                        "TRUNCATE temp_chunk_topic_post_days",
                        "DROP TABLE temp_chunk_topic_post_days"
                )
        );

        Promise<Void> topicPostUrlsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        TopicPostUrlsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("topic_post_urls")
                                .build()
                )::moveTopicPostUrls
        );
        Promise<Void> snapTimespanPostsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapTimespanPostsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.timespan_posts")
                                .build()
                )::moveSnapTimespanPosts
        );

        // Move tables that depend on "topic_posts"
        Promise.allOf(
                topicPostUrlsPromise,
                snapTimespanPostsPromise
        ).get();
    }
}
