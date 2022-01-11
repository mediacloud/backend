package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.ArrayList;
import java.util.List;

@SuppressWarnings("DuplicatedCode")
public class FeedsStoriesMapWorkflowImpl extends TableMoveWorkflow implements FeedsStoriesMapWorkflow {

    @Override
    public void moveFeedsStoriesMap() {
        Long feedsStoriesMapMaxStoriesId = this.minMaxTruncate.maxColumnValue(
                "unsharded_public.feeds_stories_map",
                "stories_id"
        );
        if (feedsStoriesMapMaxStoriesId != null) {
            List<Promise<Void>> chunkPromises = new ArrayList<>();

            // FIXME off by one?
            for (long partitionIndex = 0; partitionIndex <= feedsStoriesMapMaxStoriesId / STORIES_ID_PARTITION_CHUNK_SIZE; ++partitionIndex) {
                chunkPromises.add(
                        Async.procedure(
                                Workflow.newChildWorkflowStub(
                                        FeedsStoriesMapPartitionWorkflow.class,
                                        ChildWorkflowOptions.newBuilder()
                                                .setWorkflowId(String.format("feeds_stories_map_%02d", partitionIndex))
                                                .build()
                                )::moveFeedsStoriesMapPartition,
                                (int) partitionIndex
                        )
                );
            }

            Promise.allOf(chunkPromises).get();
        }
    }
}
