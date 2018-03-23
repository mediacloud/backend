#!/usr/bin/env perl

use strict;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use MediaWords::DB;

use MediaWords::DBI::Downloads;
use MediaWords::DBI::DownloadTexts;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use XML::LibXML;
use Data::Dumper;

use Digest::SHA qw(sha1 sha1_hex sha1_base64);

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;

sub queue_extraction($$)
{
    my ( $db, $stories_id ) = @_;

    my $args = {
        stories_id => $stories_id,
        use_cache  => 1
    };

    my $priority = $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_LOW;
    MediaWords::Job::ExtractAndVector->add_to_queue( $args, $priority );
}

# do a test run of the text extractor
sub main
{
    my ( $file, $download_ids, $unextracted, $query );

    $download_ids = [];

    GetOptions(
        'file|f=s'      => \$file,
        'downloads|d=s' => $download_ids,
        'query|q=s'     => \$query,
        'unextracted!'  => \$unextracted
    ) or die;

    unless ( $file || $download_ids || $query || $unextracted )
    {
        die( "must specify one of either --file, --download_ids, --query, or --unextracted" );
    }

    my $stories_ids;

    my $db = MediaWords::DB::connect_to_db;

    if ( scalar( @{ $download_ids } ) )
    {
        $download_ids = [ map { int( $_ ) } @{ $download_ids } ];

        my $ids = $db->get_temporary_ids_table( $download_ids );
        $stories_ids = $db->query( "SELECT stories_id from downloads where downloads_id in ( select id from $ids )" )->flat;
    }
    elsif ( $file )
    {
        open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
        $download_ids = [ map { chomp( $_ ); int( $_ ) } <DOWNLOAD_ID_FILE> ];
        my $ids = $db->get_temporary_ids_table( $download_ids );
        $stories_ids = $db->query( "SELECT stories_id from downloads where downloads_id in ( select id from $ids )" )->flat;
    }
    elsif ( $query )
    {
        $stories_ids = $db->query( $query )->flat;
    }
    elsif ( $unextracted )
    {
        $stories_ids =
          $db->query( "select stories_id from downloads where state = 'success' and type = 'content' and extracted = false" )
          ->flat;
    }
    else
    {
        die "must specify file or downloads id";
    }

    die 'no downloads found' unless scalar( @{ $stories_ids } );

    DEBUG "queueing " . scalar( @{ $stories_ids } ) . ' stories for extraction ...';

    map { queue_extraction( $db, $_ ) } @{ $stories_ids };
}

main();
