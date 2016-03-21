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

Readonly my $download_text_wild_card_query_search => q{ to_tsvector('english', download_text) @@ to_tsquery('english', ?) };

sub addDownloadChild
{
    my ( $db, $story, $row, $matching_downloads_for_story, $or_query_list ) = @_;
    my $download = XML::LibXML::Element->new( 'download' );

    my $downloads_id = $row->{ downloads_id };

    $download->setAttribute( 'downloads_id', $row->{ downloads_id } );
    $download->setAttribute( 'matching', defined( $matching_downloads_for_story->{ $downloads_id } ) ? 'true' : 'false' );

    if ( defined( $matching_downloads_for_story->{ $downloads_id } ) )
    {
        for my $or_query_term ( @{ $or_query_list } )
        {
            my $download_text_matches_or_query_term = $db->query(
"select  $download_text_wild_card_query_search as sub_query_matches from download_texts where downloads_id = ? ",
                "'$or_query_term'", $downloads_id
            )->hash->{ sub_query_matches };

            my $sub_query_match_element = XML::LibXML::Element->new( 'sub_query_term' );
            $sub_query_match_element->appendText( $or_query_term );

            $sub_query_match_element->setAttribute( 'matches', $download_text_matches_or_query_term ? 'true' : 'false' );
            $download->appendChild( $sub_query_match_element );
        }
    }

    $download->appendTextChild( 'url',  $row->{ download_url } );
    $download->appendTextChild( 'host', $row->{ host } );
    $download->appendTextChild( 'text', $row->{ download_text } );

    $story->appendChild( $download );
}

sub get_matching_downloads_for_story
{
    ( my $db, my $search_query, my $story_id ) = @_;

    my $matching_downloads_for_story = $db->query(
"select downloads.downloads_id from downloads, download_texts where $download_text_wild_card_query_search and downloads.downloads_id=download_texts.downloads_id and downloads.stories_id = ? "
          . ' order by sequence',
        $search_query, $story_id
    )->map_hashes( 'downloads_id' );

    return $matching_downloads_for_story;
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
    my ( $db, $story, $story_id, $full_ts_query, $or_query_list ) = @_;

    my $downloads_for_story = get_downloads_for_story( $db, $story_id );

    my $matching_downloads_for_story = get_matching_downloads_for_story( $db, $full_ts_query, $story_id );

    confess if ( scalar( keys %{ $matching_downloads_for_story } ) == 0 );

    while ( my $row = $downloads_for_story->hash() )
    {
        addDownloadChild( $db, $story, $row, $matching_downloads_for_story, $or_query_list );
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

sub get_matching_articles
{
    ( my $db, my $search_query ) = @_;
    my $matching_articles = $db->query(
"select stories.*, stories.url as story_url from download_texts, downloads, stories where $download_text_wild_card_query_search and downloads.downloads_id=download_texts.downloads_id and downloads.stories_id=stories.stories_id "
          . ' order by media_id, stories.stories_id',
        $search_query,
    );

    print STDERR "finished  -- search query " . localtime() . "\n";

    return $matching_articles;
}

sub get_matching_articles_within_date_range
{
    ( my $db, my $search_query, my $start_date, my $end_date ) = @_;
    my $matching_articles = $db->query(
"select stories.*, stories.url as story_url from download_texts, downloads, stories where $download_text_wild_card_query_search and downloads.downloads_id=download_texts.downloads_id and downloads.stories_id=stories.stories_id "
          . ' and publish_date >= ?  and publish_date <= ? '
          . ' order by media_id, stories.stories_id',
        $search_query, $start_date, $end_date );

    print STDERR "finished  -- search query " . localtime() . "\n";

    return $matching_articles;
}

sub get_ts_or_query_from_list
{
    ( my $ored_query_terms ) = @_;

    my $or_query = join "|", ( map { "'$_'" } @{ $ored_query_terms } );

    return $or_query;
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

sub create_calais_tags_element
{
    my ( $db, $story_id ) = @_;

    Readonly my $calais_tag_sets_id => 13;

    my $story_tag_rows = $db->query(
"SELECT tags.tags_id, tags.tag FROM stories_tags_map, tags WHERE stories_tags_map.tags_id=tags.tags_id and stories_tags_map.stories_id = ? and tags.tag_sets_id = ? ",
        $story_id, $calais_tag_sets_id
    );

    #list of calias tags
    my $calais_tags_element = XML::LibXML::Element->new( 'calais_tags' );

    while ( $story_tag_rows->into( my $tags_id, my $tag ) )
    {

        #create element for a single calais tag
        my $calais_tag_element = XML::LibXML::Element->new( 'calais_tag' );
        $calais_tag_element->setAttribute( 'tags_id', $tags_id );
        $calais_tag_element->appendText( $tag );

        $calais_tags_element->appendChild( $calais_tag_element );
    }

    return $calais_tags_element;
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
    my @or_query;

    # = (
    #                     'paulson',
    #                     'bernanke',
    #                     'bailout',
    #                     'treasury',
    #                     'troubled assets',
    #                     'tarp',
    #                     '700 billion',
    #                     'the fed',
    #                     'the federal reserve ',
    #                    );

    my Readonly $usage =
      'USAGE: ./mediawords_serach_result_to_xml --file=FILE_NAME --or_query=QUERY  [--start_date=DATE --end_date=DATE]';

    GetOptions(
        'file=s'       => \$output_file,
        'or_query=s'   => \@or_query,
        'start_date=s' => \$start_date,
        'end_date=s'   => \$end_date
    ) or die "$usage\n";

    die "$usage\n"
      unless $output_file && ( @or_query );

    die "$usage\n"
      if ( ( $start_date or $end_date ) and ( !( $start_date and $end_date ) ) );

    print STDERR "starting --  " . localtime() . "\n";

    my $db = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    print STDERR "starting -- search query " . localtime() . "\n";

    Readonly my $full_ts_query_string => get_ts_or_query_from_list( \@or_query );

    my $matching_articles;

    if ( $start_date && $end_date )
    {
        $matching_articles = get_matching_articles_within_date_range( $db, $full_ts_query_string, $start_date, $end_date );
    }
    else
    {
        $matching_articles = get_matching_articles( $db, $full_ts_query_string, $start_date, $end_date );
    }

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
            my $calais_tags_element = create_calais_tags_element( $db, $stories_id );
            $story->appendChild( $calais_tags_element );
            add_downloads_to_story( $db, $story, $stories_id, $full_ts_query_string, \@or_query );
            $media_element->appendChild( $story );
            $last_story_id = $stories_id;
        }
    }

    print $doc->toFile( $output_file, 1 );

    print STDERR "finished --  " . localtime() . "\n";
}

main();
