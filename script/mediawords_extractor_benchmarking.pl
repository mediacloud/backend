#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

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

sub test_extractor
{

    my ( $downloads ) = @_;

    my @downloads = @{ $downloads };

    say STDERR "Starting store_downloads";

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $download_results = [];

    my $dbs = MediaWords::DB::connect_to_db;

    for my $download ( @downloads )
    {
        say STDERR "Processing download $download->{downloads_id}";
        my $extract_results = MediaWords::DBI::Downloads::extractor_results_for_download( $dbs, $download );

        say "Got extract_results: " . Dumper( $extract_results );
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

        say STDERR "Will extract download IDs: " . join( ', ', @download_ids );

        $downloads = $dbs->query(
            <<EOF,
            SELECT *
            FROM downloads
            WHERE downloads_id IN (??)
EOF
            @download_ids
        )->hashes;
    }
    else
    {
        say STDERR "Will extract *all* 'content' downloads";

        $downloads = $dbs->query(
            <<EOF
            SELECT *
            FROM downloads
            WHERE type = 'content'
              AND state = 'success'
EOF
        )->hashes;
    }

    die 'no downloads found ' unless scalar( @{ $downloads } );

    say STDERR "Will extract " . scalar( @{ $downloads } ) . " downloads.";

    foreach my $iteration ( 1 .. $iterations )
    {
        say STDERR "iteration $iteration";
        test_extractor( $downloads );
    }
}

main();
