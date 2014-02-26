package org.mediacloud.crfutils;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.PrintStream;
import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;

import org.simpleframework.http.Request;
import org.simpleframework.http.Response;
import org.simpleframework.http.Status;
import org.simpleframework.http.core.Container;
import org.simpleframework.http.core.ContainerServer;
import org.simpleframework.transport.Server;
import org.simpleframework.transport.connect.Connection;
import org.simpleframework.transport.connect.SocketConnection;

public class WebServerHandler implements Container {

    public static class Task implements Runnable {

        private final Response response;
        private final Request request;
        private final ModelRunner modelRunner;

        public Task(Request request, Response response, ModelRunner modelRunner) {
            this.response = response;
            this.request = request;
            this.modelRunner = modelRunner;
        }

        @Override
        public void run() {
            try {
                PrintStream body = response.getPrintStream();

                long time = System.currentTimeMillis();
                response.setValue("Content-Type", "text/plain");
                response.setValue("Server", "CRFUtils/1.0");
                response.setDate("Date", time);
                response.setDate("Last-Modified", time);

                if (!"POST".equals(request.getMethod())) {
                    response.setStatus(Status.METHOD_NOT_ALLOWED);
                    body.println("Not POST.");
                    body.close();
                    return;
                }

                String postData = request.getContent();
                if (postData.isEmpty()) {
                    response.setStatus(Status.BAD_REQUEST);
                    body.println("Empty POST.");
                    body.close();
                    return;
                }

                try {
                    body.println(modelRunner.runModelStringReturnString(postData));
                } catch (Exception ex) {
                    response.setStatus(Status.INTERNAL_SERVER_ERROR);
                    body.println("Unable to extract: " + ex.getMessage());
                    body.close();
                    return;
                }

                body.close();

            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    private final Executor executor;
    private final ModelRunner modelRunner;

    public WebServerHandler(int size) throws IOException, FileNotFoundException, ClassNotFoundException {
        this.executor = Executors.newFixedThreadPool(size);
        this.modelRunner = new ModelRunner("../../lib/CRF/models/extractor_model");
    }

    @Override
    public void handle(Request request, Response response) {

        Task task = new Task(request, response, modelRunner);

        executor.execute(task);
    }

    public static void main(String[] list) throws Exception {

        // Read properties
        String strNumberOfThreads = System.getProperty("crf.numberOfThreads");
        if (null == strNumberOfThreads || strNumberOfThreads.isEmpty()) {
            throw new Exception("crf.numberOfThreads is null or empty.");
        }
        final int numberOfThreads = Integer.parseInt(strNumberOfThreads);
        if (numberOfThreads < 1) {
            throw new Exception("crf.numberOfThreads is below 1.");
        }

        String strHttpPort = System.getProperty("crf.httpPort");
        if (null == strHttpPort || strHttpPort.isEmpty()) {
            throw new Exception("crf.httpPort is null or empty.");
        }
        final int httpPort = Integer.parseInt(strHttpPort);
        if (httpPort < 1) {
            throw new Exception("crf.httpPort is below 1.");
        }

        System.err.println("Will spawn " + numberOfThreads + " threads.");
        System.err.println("Will listen to port " + httpPort + ".");

        System.err.println("Setting up...");
        Container container = new WebServerHandler(numberOfThreads);
        Server server = new ContainerServer(container);
        Connection connection = new SocketConnection(server);
        SocketAddress address = new InetSocketAddress(httpPort);
        System.err.println("Done.");

        connection.connect(address);

        System.err.println("Make POST requests to 127.0.0.1:" + httpPort + " with the text you want to be processed.");
    }

}
