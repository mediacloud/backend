package org.mediacloud.mrts.tables;

import io.temporal.workflow.WorkflowInterface;
import io.temporal.workflow.WorkflowMethod;

@WorkflowInterface
public interface StoriesTagsMapPartitionWorkflow {

    @WorkflowMethod
    void moveStoriesTagsMapPartition(int partitionIndex);
}
