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
use MaxEntUtils;

Readonly my $folds => 10;

sub main
{
    my $usage = "USAGE: max_ent_cross_validate_dat_file <training_dat_file> <testing_dat_file> <num_iterations> <output_path>";

    die "$usage" unless scalar (@ARGV) == 4;

    my $training_dat_file = $ARGV[0];
    
    say STDERR "training on dat file $training_dat_file";

    open my $in_fh, $training_dat_file or die "Failed to open file $@";

    my @train_data = <$in_fh>;   
    close $in_fh;

    my $testing_dat_file = $ARGV[1];    
    say STDERR "testing on dat file $testing_dat_file";
    open $in_fh, $testing_dat_file or die "Failed to open file $@";

    my @test_data = <$in_fh>;   
    close $in_fh;

    my $iterations = $ARGV[2];

    die "Iterations must be numeric\n$usage" unless int($iterations) eq $iterations;

    $iterations = int($iterations);

    my $output_dir = $ARGV[ 3 ];

    unless ( -d $output_dir ) 
    {
	make_path( $output_dir ) or die "$@";
    }

    my $output_fhs = MaxEntUtils::generate_output_fhs( $output_dir );

    {

	my $files = { train_data_file => $training_dat_file, leave_out_file => $testing_dat_file };

	MaxEntUtils::train_and_test( $files, $output_fhs, $iterations );
    }

}

main();
