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
    my $usage = "USAGE: max_ent_run_model <arff_pairs_file> <iterations> ";

    die "$usage" unless scalar (@ARGV) == 2;


    my $arff_pairs_file = $ARGV[0];
    my $iterations      = $ARGV[1];

    open my $in_fh, "<", $arff_pairs_file or die "Failed to open file $@";

    Readonly my $home_dir => $ENV{ HOME };

    say $home_dir;

    while ( my $line = <$in_fh> )
    {
	chomp( $line );

	say $line;

	my ( $arff_train_file, $arff_test_file ) = split ',' , $line;

	$arff_train_file =~ s/^~\//$home_dir\//;
	$arff_test_file =~ s/^~\//$home_dir\//;

	say "train: $arff_train_file; test $arff_test_file ";

	my $output_dir = "$arff_test_file";
	$output_dir =~ s/\.arff$//;
	$output_dir .= "_results";
	
	MaxEntUtils::create_model_and_test_from_arff_files($arff_train_file, $arff_test_file, $iterations, $output_dir );
    }
}

main();
