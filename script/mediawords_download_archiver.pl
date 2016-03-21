#!/usr/bin/env perl

# create media_tag_tag_counts table by querying the database tags / feeds / stories

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

use DBIx::Simple::MediaWords;
use XML::LibXML;
use Getopt::Long;
use Readonly;
use Carp;
use MediaWords::DBI::Downloads;
use Data::Dumper;
use Encode;
use MIME::Base64;

sub addDownloadChild
{
    my ( $db, $story, $row ) = @_;
    my $download = XML::LibXML::Element->new( 'download' );

    my $downloads_id = $row->{ downloads_id };

    $download->setAttribute( 'downloads_id', $row->{ downloads_id } );

    $download->appendTextChild( 'url',  $row->{ download_url } );
    $download->appendTextChild( 'host', $row->{ host } );

    print STDERR "Starting fetch_content\n";
    my $download_content = MediaWords::DBI::Downloads::fetch_content( $db, $row );

    my $data_section = XML::LibXML::CDATASection->new( encode_base64( encode( "utf8", $$download_content ) ) );

    my $download_content = XML::LibXML::Element->new( 'download_content' );
    $download_content->appendChild( $data_section );

    $download->appendChild( $download_content );

    $story->appendChild( $download );
}

sub get_downloads_for_story
{
    ( my $db, my $story_id ) = @_;
    my $downloads_for_story = $db->query(
"select *, url as download_url from  downloads, download_texts where stories_id = ? and downloads.downloads_id=download_texts.downloads_id order by sequence",
        $story_id
    );
    return $downloads_for_story;

}

sub add_downloads_to_story
{
    my ( $db, $story, $story_id ) = @_;

    my $downloads_for_story = get_downloads_for_story( $db, $story_id );

    while ( my $row = $downloads_for_story->hash() )
    {
        addDownloadChild( $db, $story, $row );
    }
}

sub add_feed_elements_to_story
{
    my ( $db, $story, $story_id ) = @_;

    my $feeds_for_story_id =
      $db->query( "SELECT * from feeds_stories_map where stories_id = ? order by feeds_id", $story_id );
    while ( my $row = $feeds_for_story_id->hash() )
    {
        my $feed_element = XML::LibXML::Element->new( 'feed' );
        $feed_element->setAttribute( 'feeds_id', $row->{ feeds_id } );

        $story->appendChild( $feed_element );
    }
}

sub get_matching_articles_within_date_range
{
    ( my $db, my $search_query, my $start_date, my $end_date ) = @_;

    my $matching_articles = $db->query(
"select stories.*, stories.url as story_url from download_texts, downloads, stories where downloads.downloads_id=download_texts.downloads_id and downloads.stories_id=stories.stories_id "

          #    . ' and publish_date >= ?  and publish_date <= ? '
          . ' order by media_id, stories.stories_id',

        # $start_date, $end_date
    );

    print STDERR "finished  -- search query " . localtime() . "\n";

    return $matching_articles;
}

sub create_feed_element
{
    ( my $feeds_id, my $feed_name, my $feed_url ) = @_;

    my $feed_element = XML::LibXML::Element->new( 'feed' );

    $feed_element->setAttribute( 'feeds_id', $feeds_id );

    $feed_element->appendTextChild( 'name', $feed_name );
    $feed_element->appendTextChild( 'url',  $feed_url );

    return $feed_element;
}

sub add_feeds_to_media_element
{
    ( my $db, my $media_element, my $media_id ) = @_;

    my $feeds_matching_media_id =
      $db->query( "select feeds_id, name, url from feeds where media_id = ? and feed_status = 'active'", $media_id );

    $feeds_matching_media_id->bind( my $feeds_id, my $feed_name, my $feed_url );

    while ( $feeds_matching_media_id->fetch() )
    {
        my $feed_element = create_feed_element( $feeds_id, $feed_name, $feed_url );

        $media_element->appendChild( $feed_element );
    }
}

sub create_story_element
{
    ( my $row ) = @_;

    my $story = XML::LibXML::Element->new( 'story' );

    $story->setAttribute( 'stories_id',   $row->{ stories_id } );
    $story->setAttribute( 'guid',         $row->{ stories_id } );
    $story->setAttribute( 'publish_date', $row->{ publish_date } );

    $story->appendTextChild( 'title',       $row->{ title } );
    $story->appendTextChild( 'url',         $row->{ story_url } );
    $story->appendTextChild( 'description', $row->{ description } || '' );

    return $story;
}

sub create_media_element
{
    ( my $db, my $media_id ) = @_;

    print STDERR "creating XML node for media_id $media_id\n";

    my $media_element = XML::LibXML::Element->new( 'medium' );
    $media_element->setAttribute( 'media_id', $media_id );

    my $media_row = $db->query( "SELECT * from media where media_id = ?", $media_id )->hash;

    $media_element->appendTextChild( 'name', $media_row->{ name } );
    $media_element->appendTextChild( 'url',  $media_row->{ url } );

    add_feeds_to_media_element( $db, $media_element, $media_id );

    return $media_element;
}

sub main
{

    my $output_file;

    my $start_date;
    my $end_date;

    my Readonly $usage = 'USAGE: ' . __FILE__ . ' --file=FILE_NAME [--start_date=DATE --end_date=DATE]';

    GetOptions(
        'file=s'       => \$output_file,
        'start_date=s' => \$start_date,
        'end_date=s'   => \$end_date
    ) or die "$usage\n";

    die "$usage\n"
      unless $output_file;

    die "$usage\n"
      if ( ( $start_date or $end_date ) and ( !( $start_date and $end_date ) ) );

    print STDERR "starting --  " . localtime() . "\n";

    $start_date = '2008-01-01';
    $end_date   = '2011-01-01';

    my $db = MediaWords::DB::connect_to_db;

    print STDERR "starting -- search query " . localtime() . "\n";

    my $matching_articles;

    $matching_articles = get_matching_articles_within_date_range( $db, $start_date, $end_date );

    my $doc  = XML::LibXML::Document->new();
    my $root = $doc->createElement( 'search_results' );

    $doc->setDocumentElement( $root );

    my $media_element;
    my $last_media_id = -1;

    my $last_story_id = -1;
    my $story;

    my $previous_sequence_id = -1;

    while ( my $row = $matching_articles->hash() )
    {
        if ( $last_media_id != $row->{ media_id } )
        {
            $media_element = create_media_element( $db, $row->{ media_id } );
            $root->appendChild( $media_element );
            $last_media_id = $row->{ media_id };
        }

        my $stories_id = $row->{ stories_id };
        if ( $last_story_id != $stories_id )
        {

            $story = create_story_element( $row );

            add_feed_elements_to_story( $db, $story, $stories_id );
            add_downloads_to_story( $db, $story, $stories_id );
            $media_element->appendChild( $story );
            $last_story_id = $stories_id;
        }
    }

    print $doc->toFile( $output_file, 1 );

    print STDERR "finished --  " . localtime() . "\n";
}

main();
