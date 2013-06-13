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
    my $usage = "USAGE: max_ent_run_model <arff_train_file> <arff_test_file> <iterations> <output_path>";

    die "$usage" unless scalar (@ARGV) == 4;


    my $arff_train_file = $ARGV[0];
    my $arff_test_file  = $ARGV[1];
    my $iterations      = $ARGV[2];
    my $output_dir      = $ARGV[ 3 ];

    open my $in_fh, $arff_train_file or die "Failed to open file $@";
    close $in_fh;
    open $in_fh, $arff_test_file or die "Failed to open file $@";
    close $in_fh;

    MaxEntUtils::create_model_and_test_from_arff_files($arff_train_file, $arff_test_file, $iterations, $output_dir );
}

main();
