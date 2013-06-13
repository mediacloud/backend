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

    my $cutoff = 0;

    my $output_fhs = MaxEntUtils::generate_output_fhs( $output_dir );

    for my $current_part( 0 ... $folds-1 )
    {

	say STDERR "processing part $current_part";

	my $files = MaxEntUtils::output_testing_and_training( \@out_data, $current_part, $folds );

	MaxEntUtils::train_and_test($files, $output_fhs, $iterations );

    }

}

main();
