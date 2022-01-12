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
        Workflow.newChildWorkflowStub(
                StorySentencesWorkflow.class,
                ChildWorkflowOptions.newBuilder()
                        .setWorkflowId("story_sentences")
                        .build()
        ).moveStorySentences();
    }
}
