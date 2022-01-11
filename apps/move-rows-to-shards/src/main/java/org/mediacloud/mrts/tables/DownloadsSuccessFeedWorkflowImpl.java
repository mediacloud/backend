package org.mediacloud.mrts.tables;

import io.temporal.workflow.Async;
import io.temporal.workflow.ChildWorkflowOptions;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;

import java.util.ArrayList;
import java.util.List;

@SuppressWarnings("DuplicatedCode")
public class DownloadsSuccessFeedWorkflowImpl extends TableMoveWorkflow implements DownloadsSuccessFeedWorkflow {

    @Override
    public void moveDownloadsSuccessFeed() {
        Long downloadsSuccessFeedMaxDownloadsId = this.minMaxTruncate.maxColumnValue(
                "unsharded_public.downloads_success_feed",
                "downloads_id"
        );
        if (downloadsSuccessFeedMaxDownloadsId != null) {
            List<Promise<Void>> chunkPromises = new ArrayList<>();

            // FIXME off by one?
            for (long partitionIndex = 0; partitionIndex <= downloadsSuccessFeedMaxDownloadsId / DOWNLOADS_ID_PARTITION_CHUNK_SIZE; ++partitionIndex) {
                chunkPromises.add(
                        Async.procedure(
                                Workflow.newChildWorkflowStub(
                                        DownloadsSuccessFeedPartitionWorkflow.class,
                                        ChildWorkflowOptions.newBuilder()
                                                .setWorkflowId(String.format("downloads_success_feed_%02d", partitionIndex))
                                                .build()
                                )::moveDownloadsSuccessFeedPartition,
                                (int) partitionIndex
                        )
                );
            }

            Promise.allOf(chunkPromises).get();
        }
    }
}
