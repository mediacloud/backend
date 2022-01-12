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
        Workflow.newChildWorkflowStub(
                StoriesWorkflow.class,
                ChildWorkflowOptions.newBuilder()
                        .setWorkflowId("stories")
                        .build()
        ).moveStories();
    }
}
