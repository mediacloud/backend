package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.ArrayList;
import java.util.List;

public class DownloadTextsWorkflowImpl extends TableMoveWorkflow implements DownloadTextsWorkflow {

    @Override
    public void moveDownloadTexts() {
        Long downloadTextsMaxDownloadsId = this.minMaxTruncate.maxColumnValue(
                "unsharded_public.download_texts",
                "downloads_id"
        );
        if (downloadTextsMaxDownloadsId != null) {
            List<Promise<Void>> chunkPromises = new ArrayList<>();

            for (long partitionIndex = 0; partitionIndex <= downloadTextsMaxDownloadsId / DOWNLOADS_ID_PARTITION_CHUNK_SIZE; ++partitionIndex) {
                chunkPromises.add(
                        Async.procedure(
                                Workflow.newChildWorkflowStub(
                                        DownloadTextsPartitionWorkflow.class,
                                        ChildWorkflowOptions.newBuilder()
                                                .setWorkflowId(String.format("download_texts_%02d", partitionIndex))
                                                .build()
                                )::moveDownloadTextsPartition,
                                (int) partitionIndex
                        )
                );
            }

            Promise.allOf(chunkPromises).get();
        }
    }
}
