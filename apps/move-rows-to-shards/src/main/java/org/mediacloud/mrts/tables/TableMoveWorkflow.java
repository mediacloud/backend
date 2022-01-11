package org.mediacloud.mrts.tables;

import io.temporal.activity.ActivityOptions;
import io.temporal.common.RetryOptions;
import io.temporal.workflow.Async;
import io.temporal.workflow.Promise;
import io.temporal.workflow.Workflow;
import org.mediacloud.mrts.MinMaxTruncateActivities;
import org.mediacloud.mrts.MoveRowsActivities;
import org.mediacloud.mrts.MoveRowsToShardsWorkflowImpl;
import org.mediacloud.mrts.Shared;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

public class TableMoveWorkflow {

    protected static final Logger log = LoggerFactory.getLogger(MoveRowsToShardsWorkflowImpl.class);

    protected static final String START_ID_MARKER = "**START_ID**";
    protected static final String END_ID_MARKER = "**END_ID**";

    protected static final int STORIES_ID_PARTITION_CHUNK_SIZE = 100_000_000;
    protected static final int DOWNLOADS_ID_PARTITION_CHUNK_SIZE = 100_000_000;

    protected static final String DOWNLOADS_ID_SRC_COLUMNS = """
            downloads_id,
            feeds_id,
            stories_id,
            parent,
            url,
            host,
            download_time,
            type,
            state,
            path,
            error_message,
            priority,
            sequence,
            extracted
                """;
    protected static final String DOWNLOADS_ID_DST_COLUMNS = """
            downloads_id::BIGINT,
            feeds_id::BIGINT,
            stories_id::BIGINT,
            parent,
            url,
            host,
            download_time,
            type::TEXT::public.download_type,
            state::TEXT::public.download_state,
            path,
            error_message,
            priority,
            sequence,
            extracted
                """;

    protected static final RetryOptions DEFAULT_RETRY_OPTIONS = RetryOptions.newBuilder()
            .setInitialInterval(Duration.ofSeconds(1))
            .setBackoffCoefficient(2)
            .setMaximumInterval(Duration.ofHours(2))
            .setMaximumAttempts(1000)
            .build();

    protected final MinMaxTruncateActivities minMaxTruncate = Workflow.newActivityStub(
            MinMaxTruncateActivities.class,
            ActivityOptions.newBuilder()
                    .setTaskQueue(Shared.TASK_QUEUE)
                    // If we need to rerun everything, min. / max. value or TRUNCATE might take a while to find because
                    // we'll be skipping a bunch of dead tuples
                    .setStartToCloseTimeout(Duration.ofHours(2))
                    .setRetryOptions(DEFAULT_RETRY_OPTIONS)
                    .build()
    );

    protected final MoveRowsActivities moveRows = Workflow.newActivityStub(
            MoveRowsActivities.class,
            ActivityOptions.newBuilder()
                    .setTaskQueue(Shared.TASK_QUEUE)
                    // We should be able to hopefully move at least a chunk every 2 hours
                    .setStartToCloseTimeout(Duration.ofHours(2))
                    .setRetryOptions(DEFAULT_RETRY_OPTIONS)
                    .build()
    );

    protected static String prettifySqlQuery(String query) {
        query = query.replaceAll("\\s+", " ");
        query = query.trim();
        return query;
    }

    // Helper, not a workflow method
    protected void moveTable(String srcTable, String srcIdColumn, int chunkSize, List<String> sqlQueries) {
        if (!srcTable.contains(".")) {
            throw new RuntimeException("Source table name must contain schema: " + srcTable);
        }
        if (!srcTable.startsWith("unsharded_")) {
            throw new RuntimeException("Source table name must start with 'unsharded_': " + srcTable);
        }
        if (srcIdColumn.contains(".")) {
            throw new RuntimeException("Invalid source ID column name: " + srcIdColumn);
        }

        boolean startIdMarkerFound = false;
        boolean endIdMarkerFound = false;

        for (String query : sqlQueries) {
            if (query.contains(START_ID_MARKER)) {
                startIdMarkerFound = true;
            }
            if (query.contains(END_ID_MARKER)) {
                endIdMarkerFound = true;
            }
        }

        if (!startIdMarkerFound) {
            throw new RuntimeException("SQL queries don't contain start ID marker '" + START_ID_MARKER + "': " + sqlQueries);
        }
        if (!endIdMarkerFound) {
            throw new RuntimeException("SQL queries don't contain end ID marker '" + END_ID_MARKER + "': " + sqlQueries);
        }

        Long minId = this.minMaxTruncate.minColumnValue(srcTable, srcIdColumn);
        if (minId == null) {
            log.warn("Table '" + srcTable + "' seems to be empty.");
            return;
        }

        Long maxId = this.minMaxTruncate.maxColumnValue(srcTable, srcIdColumn);
        if (maxId == null) {
            log.warn("Table '" + srcTable + "' seems to be empty.");
            return;
        }

        boolean queriesContainOnConflict = false;
        for (String query : sqlQueries) {
            if (query.contains("ON CONFLICT")) {
                queriesContainOnConflict = true;
                break;
            }
        }

        List<Promise<Void>> moveRowsPromises = new ArrayList<>();

        for (long startId = minId; startId <= maxId; startId += chunkSize) {
            long endId = startId + chunkSize - 1;

            List<String> sqlQueriesWithIds = new ArrayList<>();

            for (String query : sqlQueries) {
                query = query.replace(START_ID_MARKER, String.valueOf(startId));
                query = query.replace(END_ID_MARKER, String.valueOf(endId));

                // Make queries look nicer in Temporal's log
                query = prettifySqlQuery(query);

                if (query.contains("ON CONFLICT")) {
                    queriesContainOnConflict = true;
                }

                sqlQueriesWithIds.add(query);
            }

            if (queriesContainOnConflict) {
                // ON CONFLICT takes a share lock and doesn't release it for quite a bit so these queries need to be run
                // serially instead of in parallel
                this.moveRows.runQueriesInTransaction(sqlQueriesWithIds);
            } else {
                // Start running asynchronously and add to a list to later wait for
                moveRowsPromises.add(Async.procedure(moveRows::runQueriesInTransaction, sqlQueriesWithIds));
            }
        }

        if (!queriesContainOnConflict) {
            // If ON CONFLICT hasn't been found, just wait for them to complete in parallel
            Promise.allOf(moveRowsPromises).get();
        }

        // Lastly, truncate the table
        this.minMaxTruncate.truncateIfEmpty(srcTable);
    }
}
