package org.mediacloud.crfutils;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.net.URL;
import junit.framework.TestCase;

import org.apache.commons.io.IOUtils;
import org.apache.commons.lang.StringUtils;

public class ModelRunnerTest extends TestCase {

    private final String test_extractor_model_filename = "extractor_model";
    private final String test_input_txt = "test_input.txt";
    private final String test_output_txt = "test_output.txt";

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

        URL extractorModelURL = ModelRunnerTest.class.getResource(test_extractor_model_filename);
        if (null == extractorModelURL) {
            throw new IOException("Unable to find test extractor model '" + test_extractor_model_filename + "'");
        }
        this.extractor_model_path = extractorModelURL.getPath();
        if (null == this.extractor_model_path) {
            throw new IOException("Unable to determine extractor model path for text extractor model '" + test_extractor_model_filename + "'");
        }

        this.test_input = getResourceAsString(test_input_txt);
        if (null == this.test_input) {
            throw new IOException("Unable to read test input file '" + test_input_txt + "'");
        }

        this.test_output = getResourceAsString(test_output_txt);
        if (null == this.test_output) {
            throw new IOException("Unable to read test output file '" + test_output_txt + "'");
        }
    }

    public void testCRF() throws IOException, FileNotFoundException, ClassNotFoundException, Exception {

        ModelRunner mr = new ModelRunner(extractor_model_path);

        String[] results = mr.runModelString(this.test_input);
        String resultsString = StringUtils.join(results, "\n");

        assertEquals("CRF results are correct", test_output, resultsString);

    }

    public void testCRFReturnString() throws IOException, FileNotFoundException, ClassNotFoundException, Exception {

        ModelRunner mr = new ModelRunner(extractor_model_path);

        String resultsString = mr.runModelStringReturnString(this.test_input);

        assertEquals("CRF results are correct", test_output, resultsString);

    }

    public void testCRFMemory() throws IOException, FileNotFoundException, ClassNotFoundException, Exception {

        ModelRunner mr = new ModelRunner(extractor_model_path);

        String[] results = null;

        for (int x = 0; x < 1000; ++x) {
            results = mr.runModelString(this.test_input);
        }

        String resultsString = StringUtils.join(results, "\n");

        assertEquals("CRF results are correct", test_output, resultsString);
    }

}
