package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.ArrayList;
import java.util.List;

public class StoriesTagsMapWorkflowImpl extends TableMoveWorkflow implements StoriesTagsMapWorkflow {

    @Override
    public void moveStoriesTagsMap() {
        Long storiesTagsMapMaxStoriesId = this.minMax.maxColumnValue(
                "unsharded_public.stories_tags_map",
                "stories_id"
        );
        if (storiesTagsMapMaxStoriesId != null) {
            List<Promise<Void>> chunkPromises = new ArrayList<>();

            for (long partitionIndex = 0; partitionIndex <= storiesTagsMapMaxStoriesId / STORIES_ID_PARTITION_CHUNK_SIZE; ++partitionIndex) {
                chunkPromises.add(
                        Async.procedure(
                                Workflow.newChildWorkflowStub(
                                        StoriesTagsMapPartitionWorkflow.class,
                                        ChildWorkflowOptions.newBuilder()
                                                .setWorkflowId(String.format("stories_tags_map_%02d", partitionIndex))
                                                .build()
                                )::moveStoriesTagsMapPartition,
                                (int) partitionIndex
                        )
                );
            }

            Promise.allOf(chunkPromises).get();
        }
    }
}
