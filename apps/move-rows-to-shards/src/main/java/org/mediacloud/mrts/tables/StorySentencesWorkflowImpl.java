package org.mediacloud.mrts.tables;

import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Workflow;

public class StorySentencesWorkflowImpl extends TableMoveWorkflow implements StorySentencesWorkflow {

    @Override
    public void moveStorySentences() {
        Long storySentencesMaxStoriesId = this.minMax.maxColumnValue(
                "unsharded_public.story_sentences",
                "stories_id"
        );
        if (storySentencesMaxStoriesId != null) {
            // Move "story_sentences" partitions serially in order to truncate each partition after its move and thus
            // not run out of disk space
            for (long partitionIndex = 0; partitionIndex <= storySentencesMaxStoriesId / STORIES_ID_PARTITION_CHUNK_SIZE; ++partitionIndex) {
                Workflow.newChildWorkflowStub(
                        StorySentencesPartitionWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId(String.format("story_sentences_%02d", partitionIndex))
                                .build()
                ).moveStorySentencesPartition((int) partitionIndex);
            }
        }
    }
}
