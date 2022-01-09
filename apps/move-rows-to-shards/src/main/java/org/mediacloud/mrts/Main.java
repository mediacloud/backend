package org.mediacloud.mrts;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;
import io.temporal.client.WorkflowClient;
import io.temporal.client.WorkflowOptions;
import io.temporal.serviceclient.WorkflowServiceStubs;
import io.temporal.serviceclient.WorkflowServiceStubsOptions;
import io.temporal.worker.Worker;
import io.temporal.worker.WorkerFactory;
import io.temporal.worker.WorkerOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;

public class Main {
    private static final Logger log = LoggerFactory.getLogger(MoveRowsToShardsWorkflowImpl.class);

    private enum Action {
        WORKFLOW_WORKER,
        ACTIVITIES_WORKER,
        START_WORKFLOW_FG,
        START_WORKFLOW_BG,
        TEST_HTTP_START_WORKFLOW_FG_SERVER
    }

    private static final int TEST_HTTP_SERVER_PORT = 8080;

    public static void main(String[] args) throws InterruptedException, IOException {

        final String badArgumentExceptionMessage = """
                Pass one of the following arguments:
                                
                * 'workflow-worker' - run the workflow worker;
                * 'activities-worker' - run the activities worker;
                * 'start-workflow-fg' - start the workflow and wait for it to complete;
                * 'start-workflow-bg' - start the workflow in the background and return immediately;
                * 'test-http-start-workflow-fg-server' - run a test HTTP server on port 8080 that starts the workflow
                   and waits for it to complete.
                """;

        if (args.length != 1) {
            throw new RuntimeException(badArgumentExceptionMessage);
        }

        Action action;
        switch (args[0]) {
            case "workflow-worker" -> action = Action.WORKFLOW_WORKER;
            case "activities-worker" -> action = Action.ACTIVITIES_WORKER;
            case "start-workflow-fg" -> action = Action.START_WORKFLOW_FG;
            case "start-workflow-bg" -> action = Action.START_WORKFLOW_BG;
            case "test-http-start-workflow-fg-server" -> action = Action.TEST_HTTP_START_WORKFLOW_FG_SERVER;
            default -> throw new RuntimeException(badArgumentExceptionMessage);
        }

        final String hostname = "temporal-server";
        final int port = 7233;

        // Wait for Temporal server to appear
        boolean connected = false;
        while (!connected) {
            try {
                new Socket(hostname, port);
                connected = true;
            } catch (IOException e) {
                log.error("Unable to connect to " + hostname + ":" + port + ": " + e.getMessage());
                Thread.sleep(1000);
            }
        }
        log.info(hostname + ":" + port + " is up!");

        WorkflowServiceStubsOptions serviceStubsOptions = WorkflowServiceStubsOptions.newBuilder()
                .setTarget(hostname + ":" + port)
                .build();
        WorkflowServiceStubs service = WorkflowServiceStubs.newInstance(serviceStubsOptions);
        WorkflowClient client = WorkflowClient.newInstance(service);

        if (action == Action.WORKFLOW_WORKER || action == Action.ACTIVITIES_WORKER) {
            WorkerFactory factory = WorkerFactory.newInstance(client);

            // We'll start more workers if we need to parallelize things
            WorkerOptions workerOptions = WorkerOptions.newBuilder()
                    .setMaxConcurrentActivityExecutionSize(1)
                    .setMaxConcurrentWorkflowTaskExecutionSize(1)
                    .build();

            Worker worker = factory.newWorker(Shared.TASK_QUEUE, workerOptions);

            if (action == Action.ACTIVITIES_WORKER) {
                log.info("Starting activities worker...");
                worker.registerActivitiesImplementations(new MinMaxTruncateActivitiesImpl(), new MoveRowsActivitiesImpl());
            } else {
                log.info("Starting workflow worker...");
                worker.registerWorkflowImplementationTypes(MoveRowsToShardsWorkflowImpl.class);
            }

            factory.start();

        } else {
            WorkflowOptions workflowOptions = WorkflowOptions.newBuilder()
                    .setTaskQueue(Shared.TASK_QUEUE)
                    .setWorkflowId("move-rows-to-shards")
                    .build();
            MoveRowsToShardsWorkflow workflow = client.newWorkflowStub(MoveRowsToShardsWorkflow.class, workflowOptions);

            if (action == Action.START_WORKFLOW_FG) {
                log.info("Starting workflow in the foreground...");
                workflow.moveRowsToShards();
                log.info("Finished workflow in the foreground");

            } else if (action == Action.START_WORKFLOW_BG) {
                log.info("Starting workflow in the background...");
                WorkflowClient.start(workflow::moveRowsToShards);
                log.info("Started workflow in the background");

            } else {
                log.info("Starting HTTP server on port " + TEST_HTTP_SERVER_PORT);
                HttpServer server = HttpServer.create(new InetSocketAddress(TEST_HTTP_SERVER_PORT), 0);
                server.createContext("/start-workflow-fg", new StartWorkflowFgHandler(workflow));
                server.setExecutor(null);
                server.start();
            }
        }
    }

    static class StartWorkflowFgHandler implements HttpHandler {

        static MoveRowsToShardsWorkflow workflow = null;

        public StartWorkflowFgHandler(MoveRowsToShardsWorkflow workflow) {
            StartWorkflowFgHandler.workflow = workflow;
        }

        @Override
        public void handle(HttpExchange t) throws IOException {
            log.info("Starting workflow in the foreground...");
            workflow.moveRowsToShards();
            log.info("Finished workflow in the foreground");
            String response = "Workflow finished";
            t.sendResponseHeaders(200, response.length());
            OutputStream os = t.getResponseBody();
            os.write(response.getBytes());
            os.close();
        }
    }
}
