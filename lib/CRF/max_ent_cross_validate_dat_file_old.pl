#!/usr/bin/perl -w

use strict;

use 5.10.0;

use Text::CSV;
use Class::CSV;
use Readonly;
use Data::Dumper;
use File::Temp qw/ tempfile tempdir /;
use Env qw(HOME);
use File::Path qw(make_path remove_tree);

Readonly my $folds => 10;

sub output_testing_and_training
{
    my( $out_data, my $leave_out_part, my $parts ) = @_;

    my @test_data = @ { $out_data };

    my $part_size =   my $parts_size = int ( scalar( @test_data ) /$parts ) + 1;

    my @leave_out_data = splice @test_data, ($part_size* $leave_out_part ), $part_size;

    my ( $leave_out_data_fh, $leave_out_data_file_name ) = tempfile("/tmp/leave_out_tmpfileXXXXXX",  SUFFIX => '.dat');

    print $leave_out_data_fh @leave_out_data;

    close( $leave_out_data_fh);

    my ( $train_data_fh, $train_data_file_name ) = tempfile( "/tmp/train_tmpfileeXXXXXX", SUFFIX => '.dat');

    print $train_data_fh @test_data;

    say STDERR $leave_out_data_file_name;
    say STDERR $train_data_file_name;

    close( $train_data_fh);

    return { 
	leave_out_file =>  $leave_out_data_file_name,
	train_data_file => $train_data_file_name
    };
}

sub main
{
    my $usage = "USAGE: max_ent_cross_validate_dat_file <dat_file> <num_iterations> <output_path>";

    die "$usage" unless scalar (@ARGV) == 3;

    my $dat_file = $ARGV[0];
    
    say STDERR "dat file $dat_file";

    open my $in_fh, $dat_file or die "Failed to open file $@";

    my @out_data = <$in_fh>;   
    close $in_fh;

    my $iterations = $ARGV[1];

    die "Iterations must be numeric\n$usage" unless int($iterations) eq $iterations;

    $iterations = int($iterations);

    my $output_dir = $ARGV[ 2 ];

    unless ( -d $output_dir ) 
    {
	make_path( $output_dir ) or die "$@";
    }

    my $probabilities_file_name = "$output_dir/probabilities.txt";
    open my $probabilities_fh, '>',  $probabilities_file_name or die "Failed to open file $@";

    my $predictions_file_name =  "$output_dir/predictions.txt";;
    open my $predictions_fh, '>', $predictions_file_name or die "Failed to open file $@";

    my $expected_results_file_name =  "$output_dir/expected.txt";
    open my $expected_results_fh, '>', $expected_results_file_name or die "Failed to open file $@";

    my $parts_size = int ( scalar( @out_data ) /$folds ) + 1;

    for my $current_part( 0 ... $folds-1 )
    {

	say STDERR "processing part $current_part";

	my $files = output_testing_and_training( \@out_data, $current_part, $folds );

	say STDERR "creating model";

	my $create_model_script_path = "$HOME/Dropbox/SCOTUS_Data2/apache-opennlp-1.5.2-incubating-src/opennlp-maxent/samples/sports/run_create_model.sh";

	say STDERR "running $create_model_script_path " .  " -$iterations " . $files->{ train_data_file };
	#exit;

	system( $create_model_script_path, "-$iterations", $files->{ train_data_file } ) == 0 
	    or die "Error running create model: $?";

	

	my $model_file_name = $files->{ train_data_file };
	
	$model_file_name =~ s/\.dat$/Model\.txt/;

	say STDERR "generating probabilities";

	my $model_results_command = "$HOME/Dropbox/SCOTUS_Data2/apache-opennlp-1.5.2-incubating-src/opennlp-maxent/samples/sports/run_predict.sh  $files->{ leave_out_file } $model_file_name";
	#say STDERR $model_results_command;

	my $model_results = `$model_results_command`;
	print $probabilities_fh $model_results;

	say STDERR "generating predictions";

	my $model_prediction_command = "$HOME/Dropbox/SCOTUS_Data2/apache-opennlp-1.5.2-incubating-src/opennlp-maxent/samples/sports/run_eval.sh  $files->{ leave_out_file } $model_file_name";

	#say STDERR "$model_prediction_command";

	my $model_predictions = `$model_prediction_command`;
	print $predictions_fh $model_predictions;
    }

    my @expected_results = map { $_ =~ s/.* //; $_ } @out_data;

    print $expected_results_fh @expected_results;
}

main();
