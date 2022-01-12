package org.mediacloud.mrts;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;
import org.mediacloud.mrts.tables.*;

@SuppressWarnings("DuplicatedCode")
public class MoveRowsToShardsWorkflowImpl implements MoveRowsToShardsWorkflow {

    @Override
    public void moveRowsToShards() {
        // First level tables that don't have any dependencies
        Promise<Void> authUserRequestDailyCountsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        AuthUserRequestDailyCountsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("auth_user_request_daily_counts")
                                .build()
                )::moveAuthUserRequestDailyCounts
        );
        Promise<Void> mediaStatsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        MediaStatsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("media_stats")
                                .build()
                )::moveMediaStats
        );
        Promise<Void> mediaCoverageGapsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        MediaCoverageGapsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("media_coverage_gaps")
                                .build()
                )::moveMediaCoverageGaps
        );
        Promise<Void> storiesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        StoriesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("stories")
                                .build()
                )::moveStories
        );
        Promise<Void> downloadsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        DownloadsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("downloads")
                                .build()
                )::moveDownloads
        );
        Promise<Void> topicStoriesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        TopicStoriesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("topic_stories")
                                .build()
                )::moveTopicStories
        );
        Promise<Void> topicPostsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        TopicPostsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("topic_posts")
                                .build()
                )::moveTopicPosts
        );
        Promise<Void> snapStoriesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapStoriesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.stories")
                                .build()
                )::moveSnapStories
        );
        Promise<Void> snapMediaPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapMediaWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.media")
                                .build()
                )::moveSnapMedia
        );
        Promise<Void> snapMediaTagsMapPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapMediaTagsMapWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.media_tags_map")
                                .build()
                )::moveSnapMediaTagsMap
        );
        Promise<Void> snapStoriesTagsMapPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapStoriesTagsMapWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.stories_tags_map")
                                .build()
                )::moveSnapStoriesTagsMap
        );
        Promise<Void> snapStoryLinksPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapStoryLinksWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.story_links")
                                .build()
                )::moveSnapStoryLinks
        );
        Promise<Void> snapStoryLinkCountsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapStoryLinkCountsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.story_link_counts")
                                .build()
                )::moveSnapStoryLinkCounts
        );
        Promise<Void> snapMediumLinkCountsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapMediumLinkCountsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.medium_link_counts")
                                .build()
                )::moveSnapMediumLinkCounts
        );
        Promise<Void> snapMediumLinksPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SnapMediumLinksWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("snap.medium_links")
                                .build()
                )::moveSnapMediumLinks
        );

        Promise.allOf(
                authUserRequestDailyCountsPromise,
                mediaStatsPromise,
                mediaCoverageGapsPromise,
                storiesPromise,
                downloadsPromise,
                topicStoriesPromise,
                topicPostsPromise,
                snapStoriesPromise,
                snapMediaPromise,
                snapMediaTagsMapPromise,
                snapStoriesTagsMapPromise,
                snapStoryLinksPromise,
                snapStoryLinkCountsPromise,
                snapMediumLinkCountsPromise,
                snapMediumLinksPromise
        ).get();
    }
}
