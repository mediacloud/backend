package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

@SuppressWarnings("DuplicatedCode")
public class DownloadsWorkflowImpl extends TableMoveWorkflow implements DownloadsWorkflow {

    @Override
    public void moveDownloads() {
        // Move "downloads" first as "download_texts" depends on it
        Promise<Void> downloadsErrorPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        DownloadsErrorWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("downloads_error")
                                .build()
                )::moveDownloadsError
        );
        Promise<Void> downloadsSuccessContentPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        DownloadsSuccessContentWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("downloads_success_content")
                                .build()
                )::moveDownloadsSuccessContent
        );
        Promise<Void> downloadsSuccessFeedPromise = Async.procedure(
                Workflow.newChildWorkflowStub(
                        DownloadsSuccessFeedWorkflow.class,
                        ChildWorkflowOptions.newBuilder()
                                .setWorkflowId("downloads_success_feed")
                                .build()
                )::moveDownloadsSuccessFeed
        );
        Promise.allOf(
                downloadsErrorPromise,
                downloadsSuccessContentPromise,
                downloadsSuccessFeedPromise
        ).get();

        // Lastly, start copying "download_texts"
        Workflow.newChildWorkflowStub(
                DownloadTextsWorkflow.class,
                ChildWorkflowOptions.newBuilder()
                        .setWorkflowId("download_texts")
                        .build()
        ).moveDownloadTexts();
    }
}
