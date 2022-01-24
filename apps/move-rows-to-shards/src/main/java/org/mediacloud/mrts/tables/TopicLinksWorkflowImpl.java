package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.List;

public class TopicLinksWorkflowImpl extends TableMoveWorkflow implements TopicLinksWorkflow {

    @Override
    public void moveTopicLinks() {
        this.moveTable(
                "unsharded_public.topic_links",
                "topic_links_id",
                // 1,433,314,412 in source table
                2_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.topic_links
                            WHERE topic_links_id BETWEEN %s AND %s
                            RETURNING
                                topic_links_id,
                                topics_id,
                                stories_id,
                                url,
                                redirect_url,
                                ref_stories_id,
                                link_spidered
                        )
                        INSERT INTO sharded_public.topic_links (
                            topic_links_id,
                            topics_id,
                            stories_id,
                            url,
                            redirect_url,
                            ref_stories_id,
                            link_spidered
                        )
                            SELECT
                                topic_links_id::BIGINT,
                                topics_id::BIGINT,
                                stories_id::BIGINT,
                                url,
                                redirect_url,
                                ref_stories_id::BIGINT,
                                link_spidered
                            FROM deleted_rows
                            """, START_ID_MARKER, END_ID_MARKER))
        );

        Promise<Void> topicFetchUrlsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        TopicFetchUrlsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("topic_fetch_urls")
                                .build()
                )::moveTopicFetchUrls
        );
        Promise<Void> snapTopicLinksCrossMediaPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapTopicLinksCrossMediaWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.topic_links_cross_media")
                                .build()
                )::moveSnapTopicLinksCrossMedia
        );

        // Move tables that depend on "topic_links"
        Promise.allOf(
                topicFetchUrlsPromise,
                snapTopicLinksCrossMediaPromise
        ).get();
    }
}
