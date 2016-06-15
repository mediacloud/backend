#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::Process;
use MediaWords::Util::XML;

use XML::LibXML;
use MIME::Base64;
use Encode;
use List::Util qw (min);

sub export_downloads
{
    my ( $start_downloads_id, $end_downloads_id, $batch_number ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    my $doc  = XML::LibXML::Document->new();
    my $root = $doc->createElement( 'downloads' );

    $doc->setDocumentElement( $root );

    my $cur_downloads_id = $start_downloads_id;

    my ( $max_downloads_id ) =
      $db->query( " SELECT max( downloads_id) from downloads where type = 'feed' and state = 'success' " )->flat();

    if ( !defined( $end_downloads_id ) )
    {
        $end_downloads_id = $max_downloads_id;
    }
    else
    {
        $end_downloads_id = min( $end_downloads_id, $max_downloads_id );
    }

    while ( $cur_downloads_id <= $end_downloads_id )
    {

        my $batch_information = '';
        if ( defined( $batch_number ) )
        {
            $batch_information = "Batch $batch_number";

        }

        my $max_downloads_id_message = '';
        if ( defined( $max_downloads_id ) )
        {
            $max_downloads_id_message = " max overall downloads_id $max_downloads_id";
        }

        say STDERR "$batch_information Downloads_id $cur_downloads_id (end: $end_downloads_id) $max_downloads_id_message";

        my $download = $db->query(
" SELECT * from downloads where downloads_id >= ?  and type = 'feed' and state = 'success' order by downloads_id asc limit 1 ",
            $cur_downloads_id
        )->hash();

        last unless $download;

        my $download_content = MediaWords::DBI::Downloads::fetch_content( $db, $download );

        my $download_content_base64 = encode_base64( encode( "utf8", $$download_content ) );

        $cur_downloads_id = $download->{ downloads_id } + 1;

        next if ( $$download_content eq '(redundant feed)' );

        if ( '(redundant feed)' ne $download_content_base64 )
        {

            $download->{ encoded_download_content_base_64 } = $download_content_base64;

            $root->appendChild( xml_tree_from_hash( $download, 'download' ) );
        }

    }

    my $file_number = '';

    if ( defined( $batch_number ) )
    {
        $file_number = $batch_number;
    }

    my $file = "/tmp/downloads" . $file_number . ".xml";
    open my $OUT, ">", $file || die "$@";
    print $OUT $doc->toString || die "$@";
}

sub export_all_downloads
{

    my $db = MediaWords::DB::connect_to_db;

    my ( $max_downloads_id ) =
      $db->query( " SELECT max( downloads_id) from downloads where type = 'feed' and state = 'success' " )->flat();

    my ( $min_downloads_id ) = $db->query( " SELECT min( downloads_id) from downloads " )->flat();

    #Make sure the file start and end ranges are multiples of 1000
    my $start_downloads_id = int( $min_downloads_id / 1000 ) * 1000;

    Readonly my $download_batch_size => 1000;

    my $batch_number = 0;

    while ( $start_downloads_id <= $max_downloads_id )
    {
        export_downloads( $start_downloads_id, $start_downloads_id + $download_batch_size, $batch_number );
        $start_downloads_id += $download_batch_size;
        $batch_number++;

        #exit;
    }
}

# fork of $num_processes
sub main
{
    my ( $num_processes ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    export_all_downloads();
}

main();
