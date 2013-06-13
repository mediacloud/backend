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
    my $usage = "USAGE: max_ent_test_false_purge <input_dat_file> <output_dat_file>";

    die "$usage" unless scalar (@ARGV) == 2;

    my $input_dat_file = $ARGV[0];
    my $output_dat_file = $ARGV[1];
    
    say STDERR "input dat file $input_dat_file\noutput dat file $output_dat_file";

    MaxEntUtils::dat_file_purge_false_features( $input_dat_file, $output_dat_file );
}

main();
