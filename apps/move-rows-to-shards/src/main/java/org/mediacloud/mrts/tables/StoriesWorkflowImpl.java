package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.List;

@SuppressWarnings("DuplicatedCode")
public class StoriesWorkflowImpl extends TableMoveWorkflow implements StoriesWorkflow {

    @Override
    public void moveStories() {
        this.moveTable(
                "unsharded_public.stories",
                "stories_id",
                // 2,119,319,121 in source table
                3_000_000,
                List.of(String.format("""
                        WITH deleted_rows AS (
                            DELETE FROM unsharded_public.stories
                            WHERE stories_id BETWEEN %s AND %s
                            RETURNING
                                stories_id,
                                media_id,
                                url,
                                guid,
                                title,
                                normalized_title_hash,
                                description,
                                publish_date,
                                collect_date,
                                full_text_rss,
                                language
                        )
                        INSERT INTO sharded_public.stories (
                            stories_id,
                            media_id,
                            url,
                            guid,
                            title,
                            normalized_title_hash,
                            description,
                            publish_date,
                            collect_date,
                            full_text_rss,
                            language
                        )
                            SELECT
                                stories_id::BIGINT,
                                media_id::BIGINT,
                                url::TEXT,
                                guid::TEXT,
                                title,
                                normalized_title_hash,
                                description,
                                publish_date,
                                collect_date,
                                full_text_rss,
                                language
                            FROM deleted_rows
                                """, START_ID_MARKER, END_ID_MARKER))
        );

        Promise<Void> storiesApSyndicatedPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        StoriesApSyndicatedWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("stories_ap_syndicated")
                                .build()
                )::moveStoriesApSyndicated
        );
        Promise<Void> storyUrlsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        StoryUrlsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("story_urls")
                                .build()
                )::moveStoryUrls
        );
        Promise<Void> feedsStoriesMapPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        FeedsStoriesMapWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("feeds_stories_map")
                                .build()
                )::moveFeedsStoriesMap
        );
        Promise<Void> storiesTagsMapPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        StoriesTagsMapWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("stories_tags_map")
                                .build()
                )::moveStoriesTagsMap
        );
        Promise<Void> storySentencesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        StorySentencesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("story_sentences")
                                .build()
                )::moveStorySentences
        );
        Promise<Void> solrImportStoriesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SolrImportStoriesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("solr_import_stories")
                                .build()
                )::moveSolrImportStories
        );
        Promise<Void> solrImportedStoriesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        SolrImportedStoriesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("solr_imported_stories")
                                .build()
                )::moveSolrImportedStories
        );
        Promise<Void> topicMergedStoriesMapPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        TopicMergedStoriesMapWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("topic_merged_stories_map")
                                .build()
                )::moveTopicMergedStoriesMap
        );
        Promise<Void> storyStatisticsPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        StoryStatisticsWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("story_statistics")
                                .build()
                )::moveStoryStatistics
        );
        Promise<Void> processedStoriesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        ProcessedStoriesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("processed_stories")
                                .build()
                )::moveProcessedStories
        );
        Promise<Void> scrapedStoriesPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        ScrapedStoriesWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("scraped_stories")
                                .build()
                )::moveScrapedStories
        );
        Promise<Void> storyEnclosuresPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        StoryEnclosuresWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("story_enclosures")
                                .build()
                )::moveStoryEnclosures
        );

        // Move tables that depend on "stories"
        Promise.allOf(
                storiesApSyndicatedPromise,
                storyUrlsPromise,
                feedsStoriesMapPromise,
                storiesTagsMapPromise,
                storySentencesPromise,
                solrImportStoriesPromise,
                solrImportedStoriesPromise,
                topicMergedStoriesMapPromise,
                storyStatisticsPromise,
                processedStoriesPromise,
                scrapedStoriesPromise,
                storyEnclosuresPromise
        ).get();
    }
}
