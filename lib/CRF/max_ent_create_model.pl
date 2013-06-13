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
    my $usage = "USAGE: max_ent_create_model <dat_file> <num_iterations>";

    die "$usage" unless scalar (@ARGV) == 2;

    my $dat_file = $ARGV[0];
    
    say STDERR "dat file $dat_file";

    open my $in_fh, $dat_file or die "Failed to open file $@";

    my @out_data = <$in_fh>;   
    close $in_fh;

    my $iterations = $ARGV[1];

    die "Iterations must be numeric\n$usage" unless int($iterations) eq $iterations;

    $iterations = int($iterations);

    my $model_output_location = $dat_file; 
    $model_output_location =~ s/\.dat$/_MaxEntModel_Iterations_$iterations\.txt/;

    MaxEntUtils::create_model_at_location( $dat_file, $iterations, $model_output_location );
}

main();
