package org.mediacloud.crfutils;

import java.io.FileNotFoundException;
import java.io.IOException;
import junit.framework.Assert;
import junit.framework.TestCase;

import org.apache.commons.io.IOUtils;
import org.apache.commons.lang.StringUtils;

public class ModelRunnerTest extends TestCase {

    private final String test_extractor_model_filename = "test_extractor_model";

    private final String extractor_model_path;

    private final String test_input;
    private final String test_output;

    private static String getResourceAsString(String filename) {

        String data;

        try {
            data = IOUtils.toString(ModelRunnerTest.class.getResourceAsStream(filename), "UTF-8");
        } catch (IOException e) {
            System.err.println("File read error: " + e.getMessage());
            data = null;
        }

        return data;
    }

    public ModelRunnerTest() throws IOException {

        this.extractor_model_path = ModelRunnerTest.class.getResource(test_extractor_model_filename).getPath();

        this.test_input = getResourceAsString("test_input.txt");
        this.test_output = getResourceAsString("test_output.txt");
    }

    public void testCRF() throws IOException, FileNotFoundException, ClassNotFoundException, Exception {

        ModelRunner mr = new ModelRunner(extractor_model_path);

        String[] results = mr.runModelString(this.test_input);
        String resultsString = StringUtils.join(results, "\n");

        Assert.assertEquals("CRF results are correct", test_output, resultsString);

    }

    public void testCRFMemory() throws IOException, FileNotFoundException, ClassNotFoundException, Exception {

        ModelRunner mr = new ModelRunner(extractor_model_path);

        String[] results = null;

        for (int x = 0; x < 1000; ++x) {
            results = mr.runModelString(this.test_input);
        }

        String resultsString = StringUtils.join(results, "\n");

        Assert.assertEquals("CRF results are correct", test_output, resultsString);
    }

}
