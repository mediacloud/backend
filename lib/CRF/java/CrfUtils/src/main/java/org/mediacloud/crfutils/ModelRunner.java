package org.mediacloud.crfutils;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.Reader;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.regex.Pattern;

import cc.mallet.fst.CRF;
import cc.mallet.fst.SumLattice;
import cc.mallet.fst.SumLatticeDefault;
import cc.mallet.pipe.Pipe;
import cc.mallet.pipe.iterator.LineGroupIterator;
import cc.mallet.types.InstanceList;
import cc.mallet.types.Sequence;

public class ModelRunner {

    private final CRF crf;

    public ModelRunner(String modelFileName) throws IOException,
            FileNotFoundException, ClassNotFoundException {

        ObjectInputStream s = new ObjectInputStream(new FileInputStream(
                modelFileName));
        crf = (CRF) s.readObject();
        s.close();

        // Mallet's thread safety trick -- http://comments.gmane.org/gmane.comp.ai.mallet.devel/271
        Pipe p = crf.getInputPipe();
        p.getDataAlphabet().stopGrowth();
    }

    private String[] runModel(String testFileName) throws Exception {

        InstanceList testData = readTestData(testFileName);
        return crfOutputsToStrings(runCrfModel(testData));
    }

    String[] runModelString(String testDataString) throws Exception {

        InstanceList testData = readTestDataFromString(testDataString);
        return crfOutputsToStrings(runCrfModel(testData));
    }

    public String runModelStringReturnString(String testDataString) throws Exception {

        String[] results = runModelString(testDataString);
        return joinArrayToString("\n", results);
    }

    private ArrayList<CrfOutput> runCrfModel(InstanceList testData) {

        /*
         Runtime rt = Runtime.getRuntime();

         System.err.println("Used Memory: " + (rt.totalMemory() - rt.freeMemory()) / 1024 + " KB");
         System.err.println("Free Memory: " + rt.freeMemory() / 1024 + " KB");
         System.err.println("Total Memory: " + rt.totalMemory() / 1024 + " KB");
         System.err.println("Max Memory: " + rt.maxMemory() / 1024 + " KB");
         System.err.println("");
         */

        if ( testData.size() >  1) {
             throw new IllegalArgumentException("test data may only contain one sequence");
         }

        Sequence input = (Sequence) testData.get(0).getData();

        return predictSequence(input);

        //return crfOutputsToStrings(crfResults);
    }

    private String[] crfOutputsToStrings(ArrayList<CrfOutput> crfResults) {
        ArrayList<String> sequenceResults = new ArrayList<String>();

        for ( CrfOutput crfResult: crfResults )
        {
            sequenceResults.add( crfResult.prediction + " ");
        }

        return sequenceResults.toArray(new String[sequenceResults.size()]);
    }

    private InstanceList readTestData(String testFileName) throws FileNotFoundException {

        Reader testFile = new FileReader(new File(testFileName));
        return instanceListFromReader(testFile);
    }

    private InstanceList readTestDataFromString(final String testData) {

        Reader testFile = new StringReader(testData);
        return instanceListFromReader(testFile);
    }

    private InstanceList instanceListFromReader(Reader testFile) {

        Pipe p = crf.getInputPipe();
        p.setTargetProcessing(false);
        InstanceList testData = new InstanceList(p);
        testData.addThruPipe(
                new LineGroupIterator(testFile,
                        Pattern.compile("^\\s*$"), true));
        return testData;
    }

    class CrfOutput {
        public String prediction;
        public HashMap<String, Double> probabilities;
    };

    private ArrayList<CrfOutput> predictSequence(Sequence input) {

        // That's how SimpleTagger.apply() implements it
        Sequence output = crf.transduce(input);

        try {
            if (output.size() != input.size()) {
                     throw new RuntimeException("Failed to decode input sequence " + input);
            }
        } catch (RuntimeException e) {
            System.err.println("Exception: " + e.getMessage());
            return new ArrayList<CrfOutput>();
        }

         SumLattice lattice = new SumLatticeDefault(crf,input);

        ArrayList<CrfOutput> crfResults   = new ArrayList<CrfOutput>();
        for (int j = 0; j < input.size(); j++) {

            //System.err.println(" Input Pos " + j);

            CrfOutput crfResult = new CrfOutput();

            crfResult.probabilities = new HashMap<String, Double>();

            for ( int si = 0; si < crf.numStates(); si++) {
                // to state sj at input position ip
                // double twoStateMarginal = lattice.getXiProbability(j,crf.getState(si),crf.getState(sj));
                // probability of being in state si at input position ip
                double oneStateMarginal = lattice.getGammaProbability(j + 1, crf.getState(si));

                String stateName = crf.getState(si).getName();
                //System.err.println( "Marginal prob: " + stateName + " " +oneStateMarginal );
                crfResult.probabilities.put( stateName, oneStateMarginal);
            }


            String prediction = output.get(j).toString();

            crfResult.prediction = prediction;

            //System.err.println( "Prediction: " + prediction);

            //sequenceResults.add(prediction + " ");

            crfResults.add( crfResult);

        }

        return crfResults;
    }

    private static String joinArrayToString(String glue, String[] array) {

        int arrayLength = array.length;
        if (arrayLength == 0) {
            return null;
        }

        StringBuilder out = new StringBuilder();
        out.append(array[0]);
        for (int x = 1; x < arrayLength; ++x) {
            out.append(glue).append(array[x]);
        }

        return out.toString();
    }
}
