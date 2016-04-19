#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );

use Data::Dumper;
use MediaWords::Util::HTML;
use Data::Compare;
use Storable;
use 5.14.2;

my $_re_generate_cache = 0;
my $_test_sentences    = 0;

my $_download_data_load_file;
my $_download_data_store_file;
my $_dont_store_preprocessed_lines;
my $_dump_training_data_csv;

# do a test run of the text extractor
sub main
{
    my $full_data_file;

    my $test_file;
    my $hold_out_data_file;

    GetOptions(
        'full_data_file|f=s'     => \$full_data_file,
        'test_data_file|f=s'     => \$test_file,
        'hold_out_data_file|f=s' => \$hold_out_data_file,
    ) or die;

    die unless $full_data_file && $test_file && $hold_out_data_file;

    my $downloads = retrieve( $full_data_file );

    srand( 12345 );

    $downloads = [ shuffle @{ $downloads } ];

    my $total_downloads = scalar( @{ $downloads } );

    my $test_downloads = [ @{ $downloads }[ 0 ... int( $total_downloads * 0.8 ) ] ];
    my $heldout_downloads = [ @{ $downloads }[ ( int( $total_downloads * 0.8 ) + 1 ) ... int( $total_downloads - 1 ) ] ];

    die unless $total_downloads == scalar( @{ $test_downloads } ) + scalar( @{ $heldout_downloads } );

    say "Total_downloads: $total_downloads";
    say "Test_downloads: " . scalar( @$test_downloads );
    say "heldout downloads : " . scalar( @$heldout_downloads );

    store( $test_downloads,    $test_file )          or die "$!";
    store( $heldout_downloads, $hold_out_data_file ) or die "$!";
}

main();
