#!/usr/bin/env perl
#
# test MediaWords::Crawler::Extractor's performance against manually extracted downloads
#
# Usage:
#
# ./script/run_with_carton.sh \
#     ./script/mediawords_extractor_benchmarking.pl # extract only
#
# *or*
#
# MEDIAWORDS_EXTRACTOR_BENCHMARKING_VECTOR=1 \
#     ./script/run_with_carton.sh \
#     ./script/mediawords_extractor_benchmarking.pl # extract and vector
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use MediaWords::DBI::DownloadTexts;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use XML::LibXML;
use Data::Dumper;

use Digest::SHA qw(sha1 sha1_hex sha1_base64);

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;
use MediaWords::Languages::en;

#use XML::LibXML::Enhanced;

sub test_extract
{

    my ( $downloads ) = @_;

    my @downloads = @{ $downloads };

    say STDERR "Starting test_extract()...";

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $db = MediaWords::DB::connect_to_db;

    for my $download ( @downloads )
    {
        say STDERR "Processing download $download->{downloads_id}...";
        my $extract_results = MediaWords::DBI::Downloads::extract( $db, $download );

        say "Got extract_results: " . Dumper( $extract_results );
    }
}

sub test_extract_and_vector
{
    my ( $downloads ) = @_;

    my @downloads = @{ $downloads };

    say STDERR "Starting test_extract_and_vector()...";

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $db = MediaWords::DB::connect_to_db;

    for my $download ( @downloads )
    {
        say STDERR "Processing download $download->{downloads_id}...";
        MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, '1' );
        say STDERR "Done.";
    }
}

# do a test run of the text extractor
sub main
{

    my $dbs = MediaWords::DB::connect_to_db;

    my $file;
    my @download_ids;

    my $iterations = 1;

    GetOptions(
        'file|f=s'      => \$file,
        'downloads|d=s' => \@download_ids,
        'iterations=i'  => \$iterations
    ) or die;

    my $downloads;

    if ( @download_ids or $file )
    {
        if ( $file )
        {
            open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
            @download_ids = <DOWNLOAD_ID_FILE>;
        }

        say STDERR "Will process download IDs: " . join( ', ', @download_ids );

        $downloads = $dbs->query(
            <<EOF,
            SELECT *
            FROM downloads
            WHERE downloads_id IN (??)
            ORDER BY downloads_id
EOF
            @download_ids
        )->hashes;
    }
    else
    {
        say STDERR "Will process *all* 'content' downloads";

        $downloads = $dbs->query(
            <<EOF
            SELECT *
            FROM downloads
            WHERE type = 'content'
              AND state = 'success'
            ORDER BY downloads_id
EOF
        )->hashes;
    }

    die 'no downloads found ' unless scalar( @{ $downloads } );

    say STDERR "Will process " . scalar( @{ $downloads } ) . " downloads.";

    my $extract_and_vector = 0;
    if ( defined $ENV{ 'MEDIAWORDS_EXTRACTOR_BENCHMARKING_VECTOR' } )
    {
        $extract_and_vector = 1;
    }

    if ( $extract_and_vector )
    {
        say STDERR "Will extract *and* vector downloads.";
        say STDERR <<EOF;
Please note that running this script in \"extract and vector\" mode will store
extracted downloads in the database, so in order to repeat the performance test
you will have to reinitialize the database with unextracted downloads.
EOF
    }
    else
    {
        say STDERR "Will only extract downloads.";
    }

    foreach my $iteration ( 1 .. $iterations )
    {
        say STDERR "iteration $iteration";

        if ( $extract_and_vector )
        {
            test_extract_and_vector( $downloads );
        }
        else
        {
            test_extract( $downloads );
        }
    }
}

main();
