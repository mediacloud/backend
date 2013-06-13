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
    my $usage = "USAGE: max_ent_run_model <model_file> <data_file> <output_path>";

    die "$usage" unless scalar (@ARGV) == 3;


    my $model_file = $ARGV[0];

    my $dat_file = $ARGV[1];
    
    say STDERR "dat file $dat_file";

    open my $in_fh, $dat_file or die "Failed to open file $@";

    my @out_data = <$in_fh>;   
    close $in_fh;

    my $output_dir = $ARGV[ 2 ];

    unless ( -d $output_dir ) 
    {
	make_path( $output_dir ) or die "$@";
    }

    my $cutoff = 0;

    my $output_fhs = MaxEntUtils::generate_output_fhs( $output_dir );

    MaxEntUtils::run_model($model_file, $dat_file, $output_fhs );
}

main();
