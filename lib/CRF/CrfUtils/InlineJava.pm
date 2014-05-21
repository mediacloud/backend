#!/usr/bin/perl -w

#
# Package to access CRF model runner via Inline::Java
#
package CRF::CrfUtils::InlineJava;

use strict;
use warnings;

use 5.16.3;

use Readonly;
use Data::Dumper;
use Env qw(HOME);
use File::Spec;
use File::Basename;
use File::Slurp;

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

my $_crf_source_rt;

BEGIN
{
    use File::Basename;
    use File::Spec;
    use Cwd qw( realpath );

    # lib/CRF/CrfUtils/
    my $file_dir = dirname( __FILE__ );

    # lib/CRF/
    $_crf_source_rt = "$file_dir/../";

    $_crf_source_rt = realpath( File::Spec->canonpath( $_crf_source_rt ) );
}

sub _crf_root()
{
    # If this package gets moved to a different location, the subroutine will
    # stop reporting correct paths to MC root, so this is an attempt to warn
    # about the problem early
    if ( __PACKAGE__ ne 'CRF::CrfUtils::InlineJava' )
    {
        die 'Package name is not CRF::CrfUtils::InlineJava, the package was probably moved to a different location.' .
          ' Please update _crf_root() subroutine accordingly.';
    }

    return $_crf_source_rt;
}

BEGIN
{
    my $jar_dir = _crf_root() . '/CrfUtils/jars';

    my $jars = [ 'mallet-deps.jar', 'mallet.jar' ];

    #Assumes Unix fix later.
    $class_path = scalar( join ':', ( map { "$jar_dir/$_" } @{ $jars } ) );

    #say STDERR "classpath: $class_path";
}

sub create_model($$$)
{
    my ( $class, $training_data_file, $iterations ) = @_;

    return _create_model_inline_java( $class, $training_data_file, $iterations );
}

sub run_model_inline_java_data_array($$$)
{
    my ( $class, $model_file_name, $test_data_array ) = @_;

    #undef( $modelrunner );

    _reconnect_to_jvm_if_necessary();

    if ( !defined( $modelrunner ) )
    {
        say STDERR "Read model $model_file_name";
        $modelrunner = new org::mediacloud::crfutils::ModelRunner( $model_file_name );
    }

    return _run_model_on_array( $class, $modelrunner, $test_data_array );
}

sub _create_model_inline_java($$$)
{
    my ( $class, $training_data_file, $iterations ) = @_;

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

sub _run_model_on_array($$$)
{
    my ( $class, $modelrunner, $test_data_array ) = @_;

    _reconnect_to_jvm_if_necessary();

    my $test_data = join "\n", @{ $test_data_array };

    # If test data is empty
    unless ( $test_data )
    {
        return [];
    }

    # Returning and using a single string from a Java method is way faster than
    # returning and using an array of strings
    my $crf_results = $modelrunner->runModelString( $test_data );

    my $results = [];

    use Inline::Java qw(cast);

    for my $crf_result ( @$crf_results )
    {
        #say STDERR Dumper( $crf_result );

        my $prediction          = $crf_result->{ prediction };
        my $probability_entries = $crf_result->{ probabilities }->entrySet()->toArray();

        my @probabilities =
          map { cast( 'java.util.Map$Entry', $_ )->getKey() => cast( 'java.util.Map$Entry', $_ )->getValue() }
          @{ $probability_entries };

        my $result = {
            prediction    => $prediction,
            probabilities => { @probabilities },
        };

        say STDERR Dumper( $result );

        push $results, $result;
    }

    return $results;
}

sub _crf_modelrunner_java_src()
{
    # Compile and prepare Java class from /java/CrfUtils/
    my Readonly $crf_modelrunner_java_path =
      _crf_root() . '/java/CrfUtils/src/main/java/org/mediacloud/crfutils/ModelRunner.java';
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
