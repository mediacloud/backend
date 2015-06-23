#!/usr/bin/env perl

# reprocess all of the feeds for the give ap media source.  for each item in each feed,
# match to an existing story and set the description of the given story to the
# body.content of the feed item and regenerate the story_sentences using that description

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib", "$FindBin::Bin";
}

use Data::Dumper;
use Modern::Perl "2013";

use Feed::Scrape::MediaWords;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::StoryVectors;
use MediaWords::Util::HTML;

# if $v is a scalar, return $v, else return undef.
# we need to do this to make sure we don't get a ref back from a feed object field
sub _no_ref
{
    my ( $v ) = @_;

    return ref( $v ) ? undef : $v;
}

# lookup for item guids already reprocessed by this run of the script
my $_reprocessed_guids = {};

sub reprocess_download
{
    my ( $db, $download, $media_id ) = @_;

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );

    if ( !$content_ref )
    {
        warn( "Unable to fetch content for download $download->{ downloads_id }" );
        return;
    }

    my $feed = Feed::Scrape::MediaWords->parse_feed( $$content_ref );

    die( "Unable to parse feed for download $download->{ downloads_id }" ) unless $feed;

    my $items = [ $feed->get_item ];

    for my $item ( @{ $items } )
    {
        my $url = _no_ref( $item->link() ) || _no_ref( $item->get( 'nnd:canonicalUrl' ) ) || _no_ref( $item->guid() );
        my $guid = _no_ref( $item->guid() ) || $url;

        $guid = substr( $guid, 0, 1024 );

        next if ( $_reprocessed_guids->{ $guid } );
        $_reprocessed_guids->{ $guid } = 1;

        my $story = $db->query( "select * from stories where guid = ? and media_id = ?", $guid, $media_id )->hash;

        if ( !$story )
        {
            warn( "No story found for guid '$guid' download '$download->{ downloads_id }'" );
            next;
        }

        my $description = $item->get( 'content' );

        die( "no content found for guid '$guid' in download '$download->{ downloads_id }" ) unless ( $description );

        $description = MediaWords::Util::HTML::html_strip( $description );

        $db->query( "update stories set description = ? where stories_id = ?", $description, $story->{ stories_id } );

        say STDERR "set $story->{ stories_id } (length: " . length( $description ) . ")";

        MediaWords::StoryVectors::update_story_sentences_and_language( $db, $story );
    }
}

sub main
{
    my ( $media_id ) = @ARGV;

    die( "usage: $0 < media_id >" ) unless ( $media_id );

    my $db = MediaWords::DB::connect_to_db;

    my $ap_downloads = $db->query( <<SQL, $media_id )->hashes;
select *
    from downloads d
    where
        d.feeds_id in (
            select feeds_id from feeds f where f.media_id = ?
        ) and
        d.state = 'success' and
        d.type = 'feed'
    limit 1
SQL

    for my $download ( @{ $ap_downloads } )
    {
        reprocess_download( $db, $download, $media_id );
    }

}

main();
