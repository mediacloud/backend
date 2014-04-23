#!/usr/bin/perl -w

package CRF::CrfUtils;

use strict;

use 5.16.3;

use Text::CSV;
use Class::CSV;
use Readonly;
use Data::Dumper;
use File::Temp qw/ tempfile tempdir /;
use Env qw(HOME);
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Basename;
use File::Slurp;
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

my $modelrunner;

sub _mediacloud_root()
{
    my $dirname = dirname( __FILE__ );

    # If this package gets moved to a different location, the subroutine will
    # stop reporting correct paths to MC root, so this is an attempt to warn
    # about the problem early
    if ( __PACKAGE__ ne 'CRF::CrfUtils' )
    {
        die 'Package name is not CRF::CrfUtils, the package was probably moved to a different location.' .
          ' Please update _mediacloud_root() subroutine accordingly.';
    }

    # Assuming that this file resides in "lib/CRF/"
    my $root = File::Spec->rel2abs( "$dirname/../../" );
    unless ( $root )
    {
        die "Unable to determine absolute path to Media Cloud.";
    }

    return $root;
}

BEGIN
{
    my $jar_dir = _mediacloud_root() . '/lib/CRF/jars';

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

# sub run_model
# {
#     my ( $model_file_name, $test_data_file, $output_fhs ) = @_;
#
#     return _run_model_inline_java( $model_file_name, $test_data_file, $output_fhs );
# }

sub run_model_with_tmp_file
{
    my ( $model_file_name, $test_data_array ) = @_;

    _reconnect_to_jvm_if_necessary();

    my $test_data_file_name = _create_tmp_file_from_array( $test_data_array );

    my $mr = new org::mediacloud::crfutils::ModelRunner( $model_file_name );

    # Returning and using a single string from a Java method is way faster than
    # returning and using an array of strings
    my $results_string = $mr->runModelReturnString( $test_data_file_name );

    my $results = [ split( "\n", $results_string ) ];

    return $results;
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

    #undef( $modelrunner );

    _reconnect_to_jvm_if_necessary();

    if ( !defined( $modelrunner ) )
    {
        say STDERR "Read model ";
        $modelrunner = new org::mediacloud::crfutils::ModelRunner( $model_file_name );
    }

    return _run_model_on_array( $modelrunner, $test_data_array );
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
    my ( $modelrunner, $test_data_array ) = @_;

    _reconnect_to_jvm_if_necessary();

    my $test_data = join "\n", @{ $test_data_array };

    # Returning and using a single string from a Java method is way faster than
    # returning and using an array of strings
    my $results_string = $modelrunner->runModelStringReturnString( $test_data );

    my $results = [ split( "\n", $results_string ) ];

    return $results;
}

sub _run_model_inline_java
{
    my ( $model_file_name, $test_data_file, $output_fhs ) = @_;

    my $probabilities_fh = $output_fhs->{ probabilities_fh };

    my $predictions_fh = $output_fhs->{ predictions_fh };

    my $expected_results_fh = $output_fhs->{ expected_results_fh };

    say STDERR "generating predictions";

    say STDERR "classpath: $class_path";

    my @test_data_array = read_file( $test_data_file );

    my $foo = run_model_inline_java_data_array( $model_file_name, \@test_data_array );

    say join "\n", @{ $foo };

    exit();
}

sub _crf_modelrunner_java_src()
{
    # Compile and prepare Java class from /java/CrfUtils/
    my Readonly $crf_modelrunner_java_path =
      _mediacloud_root() . '/java/CrfUtils/src/main/java/org/mediacloud/crfutils/ModelRunner.java';
    my $crf_modelrunner_java_src = read_file( $crf_modelrunner_java_path );
    unless ( $crf_modelrunner_java_src )
    {
        die "Unable to read the ModelRunner Java class from $crf_modelrunner_java_path.";
    }

    return $crf_modelrunner_java_src;
}

use Inline
  Java      => _crf_modelrunner_java_src(),
  AUTOSTUDY => 1,
  CLASSPATH => $class_path,
  JNI       => $use_jni,
  PACKAGE   => 'main';

1;
