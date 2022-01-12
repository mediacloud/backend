package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.List;

public class TopicStoriesWorkflowImpl extends TableMoveWorkflow implements TopicStoriesWorkflow {

    @Override
    public void moveTopicStories() {
        this.moveTable(
                "unsharded_public.topic_stories",
                "topic_stories_id",
                // 165,026,730 in source table
                200_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.topic_stories
                            WHERE topic_stories_id BETWEEN %s AND %s
                            RETURNING
                                topic_stories_id,
                                topics_id,
                                stories_id,
                                link_mined,
                                iteration,
                                link_weight,
                                redirect_url,
                                valid_foreign_rss_story,
                                link_mine_error
                        )
                        INSERT INTO sharded_public.topic_stories (
                            topic_stories_id,
                            topics_id,
                            stories_id,
                            link_mined,
                            iteration,
                            link_weight,
                            redirect_url,
                            valid_foreign_rss_story,
                            link_mine_error
                        )
                            SELECT
                                topic_stories_id::BIGINT,
                                topics_id::BIGINT,
                                stories_id::BIGINT,
                                link_mined,
                                iteration::BIGINT,
                                link_weight,
                                redirect_url,
                                valid_foreign_rss_story,
                                link_mine_error
                            FROM deleted_rows
                            """, START_ID_MARKER, END_ID_MARKER))
        );

        Promise<Void> topicLinksPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        TopicLinksWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("topic_links")
                                .build()
                )::moveTopicLinks
        );
        Promise<Void> snapTopicStoriesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapTopicStoriesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.topic_stories")
                                .build()
                )::moveSnapTopicStories
        );
        Promise<Void> snapLiveStoriesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapLiveStoriesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.live_stories")
                                .build()
                )::moveSnapLiveStories
        );

        // Move tables that depend on "topic_stories"
        Promise.allOf(
                topicLinksPromise,
                snapTopicStoriesPromise,
                snapLiveStoriesPromise
        ).get();
    }
}
