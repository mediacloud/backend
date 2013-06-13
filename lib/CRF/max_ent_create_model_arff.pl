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
    my $usage = "USAGE: max_ent_create_model_arff <arff_file> <num_iterations>";

    die "$usage" unless scalar (@ARGV) == 2;

    my $arff_file = $ARGV[0]; 
    my $iterations = $ARGV[1];

    say STDERR "arff file $arff_file";

    open my $in_fh, $arff_file or die "Failed to open file $@";

    my $model_file_name = MaxEntUtils::create_model_from_arff_file( $arff_file, $iterations);

    say "Created model $model_file_name";
}

main();
