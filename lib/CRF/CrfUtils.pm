#!/usr/bin/perl -w

package CRF::CrfUtils;

use strict;

use 5.18.1;

use Text::CSV;
use Class::CSV;
use Readonly;
use Data::Dumper;
use File::Temp qw/ tempfile tempdir /;
use Env qw(HOME);
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Basename;
use MediaWords::Util::Config;

use Inline (
    Java => 'STUDY',

    # Increase memory available to Java to 1 GB because otherwise the extractor
    # runs out of memory after 1000 extractions
    EXTRA_JAVA_ARGS => '-Xmx1G'
);

my $class_path;

my $pid_connected_to_jvm = $$;

my $use_jni = 0;

my $crf;

BEGIN
{
    my $_dirname      = dirname( __FILE__ );
    my $_dirname_full = File::Spec->rel2abs( $_dirname );

    my $jar_dir = "$_dirname_full/jars";

    my $jars = [ 'mallet-deps.jar', 'mallet.jar' ];

    #Assumes Unix fix later.
    $class_path = scalar( join ':', ( map { "$jar_dir/$_" } @{ $jars } ) );

    my $config = MediaWords::Util::Config::get_config();

    if ( $config->{ mediawords }->{ inline_java_jni } eq 'yes' )
    {
        $use_jni = 1;
    }
    else
    {
        $use_jni = 0;
    }

    #say STDERR "classpath: $class_path";
}

sub create_model
{
    my ( $training_data_file, $iterations ) = @_;

    return _create_model_inline_java( $training_data_file, $iterations );
}

sub run_model
{
    my ( $model_file_name, $test_data_file, $output_fhs ) = @_;

    return _run_model_inline_java( $model_file_name, $test_data_file, $output_fhs );
}

sub run_model_with_tmp_file
{
    my ( $model_file_name, $test_data_array ) = @_;

    _reconnect_to_jvm_if_necessary();

    my $test_data_file_name = _create_tmp_file_from_array( $test_data_array );

    my $foo = model_runner->run_model( $test_data_file_name, $model_file_name );

    return $foo;
}

sub run_model_with_separate_exec
{
    my ( $model_file_name, $test_data_array ) = @_;

    my $test_data_file_name = _create_tmp_file_from_array( $test_data_array );

    my $output = `java -cp  $class_path cc.mallet.fst.SimpleTagger --model-file  $model_file_name $test_data_file_name `;

    return [ split "\n", $output ];
}

sub run_model_inline_java_data_array
{
    my ( $model_file_name, $test_data_array ) = @_;

    #undef( $crf );

    _reconnect_to_jvm_if_necessary();

    if ( !defined( $crf ) )
    {
        say STDERR "Read model ";
        $crf = model_runner->readModel( $model_file_name );
    }

    return _run_model_on_array( $crf, $test_data_array );
}

sub train_and_test
{
    my ( $files, $output_fhs, $iterations ) = @_;

    my $model_file_name = create_model( $files->{ train_data_file }, $iterations );

    run_model( $model_file_name, $files->{ leave_out_file }, $output_fhs );
}

sub _create_model_inline_java
{
    my ( $training_data_file, $iterations ) = @_;

    say "Entering _create_model_inline_java()";

    use Inline (
        Java  => 'STUDY',
        STUDY => [
            qw ( cc.mallet.fst.SimpleTagger
              java.io.FileReader java.io.File )
        ],
        AUTOSTUDY => 1,
        JNI       => $use_jni,
        CLASSPATH => $class_path,
        PACKAGE   => 'main'
    );

    _reconnect_to_jvm_if_necessary();

    my $model_file_name = $training_data_file;

    $model_file_name =~ s/\.dat$/Model\.txt/;

    say "Model File: $model_file_name";

    my $foo = cc::mallet::fst::SimpleTagger->main(
        [ "--train", "true", "--iterations", $iterations, "--model-file", $model_file_name, $training_data_file ] );

    return;
}

# reconnect to the JVM if the PID of this process changes
# I'm not sure this is necessary since we're not running in shared JVM mode but better safe -- DRL
sub _reconnect_to_jvm_if_necessary()
{
    if ( $pid_connected_to_jvm != $$ )
    {
        say STDERR "reconnecting to JVM: expected pid $pid_connected_to_jvm actual pid $$";
        Inline::Java->reconnect_JVM();
        $pid_connected_to_jvm = $$;
    }
}

sub _create_tmp_file_from_array
{
    my ( $test_data_array ) = @_;

    my ( $test_data_fh, $test_data_file_name ) = tempfile( "/tmp/tested_arrayXXXXXX", SUFFIX => '.dat' );

    print $test_data_fh join "\n", @{ $test_data_array };

    close( $test_data_fh );

    return $test_data_file_name;
}

sub _run_model_on_array
{
    my ( $crf, $test_data_array ) = @_;

    _reconnect_to_jvm_if_necessary();

    my $test_data = join "\n", @{ $test_data_array };

    my $foo = model_runner->run_model_string( $test_data, $crf );

    return $foo;
}

sub _run_model_inline_java
{
    my ( $model_file_name, $test_data_file, $output_fhs ) = @_;

    my $probabilities_fh = $output_fhs->{ probabilities_fh };

    my $predictions_fh = $output_fhs->{ predictions_fh };

    my $expected_results_fh = $output_fhs->{ expected_results_fh };

    my $create_model_script_path = "$HOME/Applications/mallet-2.0.7/run_simple_tagger.sh";

    say STDERR "generating predictions";

    say STDERR "classpath: $class_path";

    open my $test_data_file_fh, '<', $test_data_file;

    my @test_data_array = <$test_data_file_fh>;

    my $foo = run_model_inline_java_data_array( $model_file_name, \@test_data_array );

    say join "\n", @{ $foo };

    exit();
}

use Inline
  JAVA => <<'END_JAVA', AUTOSTUDY => 1, CLASSPATH => $class_path, JNI => $use_jni, PACKAGE => 'main';

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.Reader;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.regex.Pattern;

import cc.mallet.fst.CRF;
import cc.mallet.fst.SimpleTagger;
import cc.mallet.pipe.Pipe;
import cc.mallet.pipe.iterator.LineGroupIterator;
import cc.mallet.types.InstanceList;
import cc.mallet.types.Sequence;


public class model_runner {

	public static void main(String[] args) throws Exception {
		run_model(args[0], args[1]);
	}

	public static String[] run_model(String testFileName, String modelFileName)
			throws Exception {

		CRF crf = readModel(modelFileName);
		InstanceList testData = readTestData(testFileName, crf);


		return run_model_impl(testData, crf);
	}

	public static String[] run_model_string(String testDataString, String modelFileName)
			throws Exception {
		CRF crf = readModel(modelFileName);
		InstanceList testData = readTestDataFromString(testDataString, crf);

		
		return run_model_impl(testData, crf);
	}

	public static String[] run_model_string(String testDataString, CRF crf)
			throws Exception {
		InstanceList testData = readTestDataFromString(testDataString, crf);

		return run_crf_model(testData, crf);
	}

	private static String[] run_model_impl(InstanceList testData,
			CRF model) throws IOException, FileNotFoundException,
			ClassNotFoundException {
		CRF crf = model;

		return run_crf_model(testData, crf);
	}

	private static String[] run_crf_model(InstanceList testData, CRF crf) {
        if (true) {
            Runtime rt = Runtime.getRuntime();

            System.err.println("Used Memory: " + (rt.totalMemory() - rt.freeMemory()) / 1024 + " KB");
            System.err.println("Free Memory: " + rt.freeMemory() / 1024 + " KB");
            System.err.println("Total Memory: " + rt.totalMemory() / 1024 + " KB");
            System.err.println("Max Memory: " + rt.maxMemory() / 1024 + " KB");
        }

		ArrayList<String> results = new ArrayList<String>();
		for (int i = 0; i < testData.size(); i++) {
			Sequence input = (Sequence) testData.get(i).getData();

			ArrayList<String> predictions = predictSequence(crf, input);

			results.addAll(predictions);

			// return results.toArray(new String[0]);
			// return ret;

		}
		return results.toArray(new String[0]);
	}

	private static InstanceList readTestData(String testFileName, CRF crf)
			throws FileNotFoundException {

		Reader testFile = new FileReader(new File(testFileName));

		return instanceListFromReader(testFile, crf);
	}

	private static InstanceList readTestDataFromString(final String testData, CRF crf)
	{

		Reader testFile = new StringReader(testData);

		return instanceListFromReader(testFile, crf);
	}

	private static InstanceList instanceListFromReader(Reader testFile, CRF crf) {
		Pipe p = crf.getInputPipe();
//		p.getTargetAlphabet().lookupIndex(defaultOption.value);
		p.setTargetProcessing(false);
		InstanceList testData = new InstanceList(p);
	      testData.addThruPipe(
	          new LineGroupIterator(testFile,
	            Pattern.compile("^\\s*$"), true));
		return testData;
	}

	public static CRF readModel(String modelFileName) throws IOException,
			FileNotFoundException, ClassNotFoundException {
		ObjectInputStream s = new ObjectInputStream(new FileInputStream(
				modelFileName));
		CRF crf = null;
		crf = (CRF) s.readObject();
		s.close();
		return crf;
	}

	private static ArrayList<String> predictSequence(CRF crf,
			Sequence input) {

		ArrayList<String> sequenceResults = new ArrayList<String>();
		int nBestOption = 1;

		Sequence[] outputs = SimpleTagger.apply(crf, input, nBestOption);
		int k = outputs.length;
		boolean error = false;
		for (int a = 0; a < k; a++) {
			if (outputs[a].size() != input.size()) {
				// logger.info("Failed to decode input sequence " + i
				// + ", answer " + a);
				error = true;
			}
		}

		if (!error) {
			for (int j = 0; j < input.size(); j++) {
				StringBuffer buf = new StringBuffer();
				for (int a = 0; a < k; a++) {
					String prediction = outputs[a].get(j).toString();
					buf.append(prediction).append(" ");
					sequenceResults.add(prediction + " ");
				}
			}
		}

		return sequenceResults;
	}
}

END_JAVA

1;
