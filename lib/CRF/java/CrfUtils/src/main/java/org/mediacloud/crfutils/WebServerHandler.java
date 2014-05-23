package org.mediacloud.crfutils;

import java.io.IOException;
import java.io.PrintStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;

import com.google.gson.Gson;
import org.simpleframework.http.Request;
import org.simpleframework.http.Response;
import org.simpleframework.http.Status;
import org.simpleframework.http.core.Container;
import org.simpleframework.http.core.ContainerServer;
import org.simpleframework.transport.Server;
import org.simpleframework.transport.connect.Connection;
import org.simpleframework.transport.connect.SocketConnection;

public class WebServerHandler implements Container {

    // Path to CRF model (absolute or relative to lib/CRF/java/CrfUtils/)
    private final static String CRF_MODEL_PATH = "../../../../lib/MediaWords/Util/models/crf_extractor_model";

    // Server identifier
    private final static String SERVER_IDENTIFIER = "CRFUtils/1.0";

    // Default HTTP port to listen no (if there isn't one set in the configuration)
    private final static int DEFAULT_HTTP_PORT = 8441;

    public static class Task implements Runnable {

        private final Response response;
        private final Request request;

        // One modelRunner per thread
        private static final ThreadLocal< ModelRunner> threadLocal
                = new ThreadLocal< ModelRunner>() {
                    @Override
                    protected ModelRunner initialValue() {

                        ModelRunner modelRunner;

                        try {
                            System.err.println("Creating new CRF model runner for thread " + Thread.currentThread().getName());
                            modelRunner = new ModelRunner(CRF_MODEL_PATH);
                        } catch (IOException e) {
                            System.err.println("Unable to initialize CRF model runner: " + e.getMessage());
                            return null;
                        } catch (ClassNotFoundException e) {
                            System.err.println("Unable to find CRF model runner class: " + e.getMessage());
                            return null;
                        }

                        return modelRunner;
                    }
                };

        private final static String dateFormat = "[dd/MMM/yyyy:HH:mm:ss Z]";
        private final static SimpleDateFormat dateFormatter = new SimpleDateFormat(dateFormat);

        public Task(Request request, Response response) {
            this.response = response;
            this.request = request;
        }

        private static void printAccessLog(Request request, Response response, long responseLength) {

            String referrer = request.getValue("Referrer");
            if (null == referrer || referrer.isEmpty()) {
                referrer = "-";
            }

            StringBuilder logLine = new StringBuilder();
            logLine.append("[").append(Thread.currentThread().getName()).append("] ");
            logLine.append(request.getClientAddress().getHostName());
            logLine.append(" ");
            logLine.append(dateFormatter.format(new Date()));
            logLine.append(" \"");
            logLine.append(request.getMethod()).append(" ");
            logLine.append(request.getPath()).append(" ");
            logLine.append("HTTP/").append(request.getMajor()).append(".").append(request.getMinor());
            logLine.append("\" ");
            logLine.append(response.getStatus().code).append(" ");
            logLine.append(responseLength).append(" ");
            logLine.append("\"").append(referrer).append("\" ");
            logLine.append("\"").append(request.getValue("User-Agent")).append("\"");

            System.out.println(logLine);
        }

        private static String exceptionStackTraceToString(Exception e) {

            StringWriter sw = new StringWriter();
            PrintWriter pw = new PrintWriter(sw);
            e.printStackTrace(pw);
            return sw.toString();
        }

        @Override
        public void run() {

            Gson gson = new Gson();

            try {

                String stringResponse;

                long time = System.currentTimeMillis();
                response.setContentType("text/plain");
                response.setValue("Server", SERVER_IDENTIFIER);
                response.setDate("Date", time);
                response.setDate("Last-Modified", time);

                if (!"POST".equals(request.getMethod())) {
                    response.setStatus(Status.METHOD_NOT_ALLOWED);
                    response.setValue("Allow", "POST");
                    stringResponse = "Not POST.\n";
                } else {

                    String postData = request.getContent();
                    if (null == postData || postData.isEmpty()) {
                        response.setStatus(Status.BAD_REQUEST);
                        stringResponse = "Empty POST.\n";

                    } else {

                        try {

                            ModelRunner modelRunner = threadLocal.get();
                            if (null == modelRunner) {
                                throw new Exception("Unable to initialize CRF model runner.");
                            }

                            ModelRunner.CrfOutput[] crfResults = modelRunner.runModelString(postData);

                            if (null == crfResults) {
                                throw new Exception("CRF processing results are nil.");
                            }

                            response.setStatus(Status.OK);
                            stringResponse = gson.toJson(crfResults);

                        } catch (Exception e) {

                            String errorMessage = "Unable to extract: " + exceptionStackTraceToString(e);

                            response.setStatus(Status.INTERNAL_SERVER_ERROR);

                            //TODO format error as JSON HashMap
                            stringResponse = gson.toJson( errorMessage );
                        }

                    }
                }

                PrintStream body = response.getPrintStream();
                body.print(stringResponse);
                body.close();

                printAccessLog(request, response, stringResponse.getBytes().length);

            } catch (IOException e) {

                String errorMessage = exceptionStackTraceToString(e);
                System.err.println("Request failed: " + errorMessage);
            }
        }
    }

    class SimpleThreadFactory implements ThreadFactory {

        private int counter = 0;
        private final String THREAD_NAME_PREFIX = "http";

        @Override
        public Thread newThread(Runnable r) {
            return new Thread(r, THREAD_NAME_PREFIX + "-" + (counter++));
        }

    }

    private final Executor executor;
    private final SimpleThreadFactory threadFactory;

    public WebServerHandler(int size) {
        this.threadFactory = new SimpleThreadFactory();
        this.executor = Executors.newFixedThreadPool(size, this.threadFactory);
    }

    @Override
    public void handle(Request request, Response response) {

        Task task = new Task(request, response);

        executor.execute(task);
    }

    public static void main(String[] list) throws Exception {

        String httpListenHost;
        int httpListenPort;

        // Read properties
        String httpListen = System.getProperty("crf.httpListen");
        if (null == httpListen) {
            throw new Exception("crf.httpListen is null.");
        }
        if (httpListen.isEmpty()) {
            httpListen = "0.0.0.0:8441";
        }

        if (httpListen.contains(":")) {
            httpListenHost = httpListen.split(":")[0];
            httpListenPort = Integer.parseInt(httpListen.split(":")[1]);
        } else {
            httpListenHost = httpListen;
            httpListenPort = DEFAULT_HTTP_PORT;
        }

        if (httpListenHost.isEmpty()) {
            throw new Exception("Unable to determine host to listen to from crf.httpListen = " + httpListen);
        }
        if (httpListenPort < 1) {
            throw new Exception("Unable to determine port to listen to from crf.httpListen = " + httpListen);
        }

        String strNumberOfThreads = System.getProperty("crf.numberOfThreads");
        if (null == strNumberOfThreads || strNumberOfThreads.isEmpty()) {
            throw new Exception("crf.numberOfThreads is null or empty.");
        }
        final int numberOfThreads = Integer.parseInt(strNumberOfThreads);
        if (numberOfThreads < 1) {
            throw new Exception("crf.numberOfThreads is below 1.");
        }

        System.err.println("Will listen to " + httpListenHost + ":" + httpListenPort + ".");
        System.err.println("Will spawn " + numberOfThreads + " threads.");

        // Start the CRF model runner web service
        System.err.println("Setting up...");
        Container container = new WebServerHandler(numberOfThreads);
        Server server = new ContainerServer(container);
        Connection connection = new SocketConnection(server);
        SocketAddress address = new InetSocketAddress(httpListenHost, httpListenPort);
        System.err.println("Done.");

        connection.connect(address);

        System.err.println("Make POST requests to 127.0.0.1:" + httpListenPort + " with the text you want to run the CRF model against.");
    }

}
