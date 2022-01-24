package org.mediacloud.mrts;

import io.temporal.workflow.WorkflowInterface;
import io.temporal.workflow.WorkflowMethod;

@WorkflowInterface
public interface MoveRowsToShardsWorkflow {

    @WorkflowMethod
    void moveRowsToShards();
}
