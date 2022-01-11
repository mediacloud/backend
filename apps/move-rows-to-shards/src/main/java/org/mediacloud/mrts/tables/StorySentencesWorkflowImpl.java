package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.ArrayList;
import java.util.List;

public class StorySentencesWorkflowImpl extends TableMoveWorkflow implements StorySentencesWorkflow {

    @Override
    public void moveStorySentences() {
        Long storySentencesMaxStoriesId = this.minMaxTruncate.maxColumnValue(
                "unsharded_public.story_sentences",
                "stories_id"
        );
        if (storySentencesMaxStoriesId != null) {
            List<Promise<Void>> chunkPromises = new ArrayList<>();

            // FIXME off by one?
            for (long partitionIndex = 0; partitionIndex <= storySentencesMaxStoriesId / STORIES_ID_PARTITION_CHUNK_SIZE; ++partitionIndex) {
                chunkPromises.add(
                        Async.procedure(
                                Workflow.newChildWorkflowStub(
                                        StorySentencesPartitionWorkflow.class,
                                        ChildWorkflowOptions.newBuilder()
                                                .setWorkflowId(String.format("story_sentences_%02d", partitionIndex))
                                                .build()
                                )::moveStorySentencesPartition,
                                (int) partitionIndex
                        )
                );
            }

            Promise.allOf(chunkPromises).get();
        }
    }
}
