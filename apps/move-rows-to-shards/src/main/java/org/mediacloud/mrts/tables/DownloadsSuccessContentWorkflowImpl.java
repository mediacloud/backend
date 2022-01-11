package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.ArrayList;
import java.util.List;

@SuppressWarnings("DuplicatedCode")
public class DownloadsSuccessContentWorkflowImpl extends TableMoveWorkflow implements DownloadsSuccessContentWorkflow {

    @Override
    public void moveDownloadsSuccessContent() {
        Long downloadsSuccessContentMaxDownloadsId = this.minMaxTruncate.maxColumnValue(
                "unsharded_public.downloads_success_content",
                "downloads_id"
        );
        if (downloadsSuccessContentMaxDownloadsId != null) {
            List<Promise<Void>> chunkPromises = new ArrayList<>();

            for (long partitionIndex = 0; partitionIndex <= downloadsSuccessContentMaxDownloadsId / DOWNLOADS_ID_PARTITION_CHUNK_SIZE; ++partitionIndex) {
                chunkPromises.add(
                        Async.procedure(
                                Workflow.newChildWorkflowStub(
                                        DownloadsSuccessContentPartitionWorkflow.class,
                                        ChildWorkflowOptions.newBuilder()
                                                .setWorkflowId(String.format("downloads_success_content_%02d", partitionIndex))
                                                .build()
                                )::moveDownloadsSuccessContentPartition,
                                (int) partitionIndex
                        )
                );
            }

            Promise.allOf(chunkPromises).get();
        }
    }
}
