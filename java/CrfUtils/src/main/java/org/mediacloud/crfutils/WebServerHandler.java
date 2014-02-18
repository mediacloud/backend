package org.mediacloud.crfutils;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.PrintStream;
import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;
import java.util.logging.Level;
import java.util.logging.Logger;

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
        Container container = new WebServerHandler(32);
        Server server = new ContainerServer(container);
        Connection connection = new SocketConnection(server);
        SocketAddress address = new InetSocketAddress(8441);

        connection.connect(address);
    }

}
