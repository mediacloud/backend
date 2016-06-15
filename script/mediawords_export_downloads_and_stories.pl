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
use Parallel::ForkManager;

sub get_story_downloads
{
    my ( $db, $story ) = @_;

    die unless defined( $story->{ stories_id } );

    my $story_downloads =
      $db->query( " SELECT * FROM downloads where stories_id = ? order by sequence asc ", $story->{ stories_id } )->hashes;

    #say STDERR "Got story downloads ";
    #say STDERR Dumper( $story_downloads);

    return $story_downloads;
}

sub get_story_children_for_feed_download
{
    my ( $db, $download ) = @_;

    my $story_children =
      $db->query( " select * from stories where stories_id in ( select stories_id from downloads where parent  = ?  ) ",
        $download->{ downloads_id } )->hashes;

    return $story_children;
}

sub get_xml_element_for_download($$)
{
    my ( $db, $download ) = @_;

    my $download_content_base64 = _get_base_64_encoded_download_content( $db, $download );

    $download->{ encoded_download_content_base_64 } = $download_content_base64;

    my $download_xml = xml_tree_from_hash( $download, 'download' );
}

sub process_feed_download
{
    my ( $db, $download ) = @_;

    #say STDERR Dumper ( $download );

    my $story_children = get_story_children_for_feed_download( $db, $download );

    my $story_child_count = scalar( @{ $story_children } );

    #say STDERR "$story_child_count stories for downloads";

    if ( $story_child_count > 0 )
    {

        #say Dumper( $download );
    }
    else
    {
        return;
    }

    my $download_xml = get_xml_element_for_download( $db, $download );

    die if scalar( @{ $story_children } ) <= 0;

    my $child_stories_xml = XML::LibXML::Element->new( 'child_stories' );

    my $stories_added = 0;

    foreach my $story_child ( @{ $story_children } )
    {
        my $story_xml = xml_tree_from_hash( $story_child, 'story' );

        #say STDERR Dumper ( $child_story );
        my $story_downloads = get_story_downloads( $db, $story_child );

        # SKIP stories with incomplete downloads
        next if scalar( @{ $story_downloads } ) == 0;
        next if scalar( grep { $_->{ state } ne 'success' } @{ $story_downloads } ) != 0;

        my $story_downloads_xml = XML::LibXML::Element->new( 'story_downloads' );

        foreach my $story_download ( @{ $story_downloads } )
        {
            $story_downloads_xml->appendChild( get_xml_element_for_download( $db, $story_download ) );
        }

        $story_xml->appendChild( $story_downloads_xml );

        $child_stories_xml->appendChild( $story_xml );

        $stories_added = 1;
    }

    return if !$stories_added;    # No completely downloaded stories, skip the download

    die "Empty child_stories " unless $child_stories_xml->hasChildNodes();

    $download_xml->appendChild( $child_stories_xml );

    return $download_xml;
}

sub _get_base_64_encoded_download_content($$)
{

    my ( $db, $download ) = @_;

    my $download_content = MediaWords::DBI::Downloads::fetch_content( $db, $download );

    my $download_content_base64 = encode_base64( encode( "utf8", $$download_content ) );

    return $download_content_base64;
}

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

    my $downloads_added = 0;

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

    while ( $cur_downloads_id <= $end_downloads_id )
    {

        my $download = $db->query(
" SELECT * from downloads where downloads_id >= ?  and downloads_id <= ? and type = 'feed' and state = 'success' order by downloads_id asc limit 1 ",
            $cur_downloads_id, $end_downloads_id
        )->hash();

        last unless $download;

        # my $download_content_base64 = _get_base_64_encoded_download_content( $db, $download );

        $cur_downloads_id = $download->{ downloads_id } + 1;

        #$download->{ encoded_download_content_base_64 } = $download_content_base64;

        my $download_xml = process_feed_download( $db, $download );

        if ( defined( $download_xml ) )
        {
            $downloads_added = 1;
            $root->appendChild( $download_xml );
        }
    }

    my $file_number = '';

    if ( defined( $batch_number ) )
    {
        $file_number = $batch_number;
    }

    my $file = "/tmp/downloads" . $file_number . ".xml";

    if ( $downloads_added )
    {
        open my $OUT, ">", $file || die "$@";
        print $OUT $doc->toString( 2 ) || die "$@";
    }
}

sub export_all_downloads
{

    my $db = MediaWords::DB::connect_to_db;

    my ( $max_downloads_id ) =
      $db->query( " SELECT max( downloads_id) from downloads where type = 'feed' and state = 'success' " )->flat();

    my ( $min_downloads_id ) = $db->query( " SELECT min( downloads_id) from downloads " )->flat();

    die "No downloads " unless defined( $min_downloads_id );

    #Make sure the file start and end ranges are multiples of 1000
    my $start_downloads_id = int( $min_downloads_id / 1000 ) * 1000;

    Readonly my $download_batch_size => 100;

    my $batch_number = 0;

    my $pm = new Parallel::ForkManager( 15 );
    while ( $start_downloads_id <= $max_downloads_id )
    {
        unless ( $pm->start )
        {

            export_downloads( $start_downloads_id, $start_downloads_id + $download_batch_size, $batch_number );
            $pm->finish;
        }

        $start_downloads_id += $download_batch_size;
        $batch_number++;

        #exit;
    }

    say "Waiting for children";

    $pm->wait_all_children;

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
