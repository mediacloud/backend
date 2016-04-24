#!/usr/bin/env perl

# import stories using one of the MediaWords::ImportStories::* modules

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::ImportStories::ScrapeHTML;
use MediaWords::ImportStories::Feedly;

my $_import_module_lookup = {
    feedly => 'MediaWords::ImportStories::Feedly',
    scrapehtml => 'MediaWords::ImportStories::ScrapeHTML'
};

sub get_media_from_options
{
    my ( $db, $media_id, $tags_id_media, $import_module ) = @_;

    die( "must specify --media_id or --tags_id_media" ) unless ( $media_id || $tags_id_media );

    $media_id      ||= 0;
    $tags_id_media ||= 0;

    my $media = $db->query( <<SQL, $tags_id_media, $import_module )->hashes;
select m.*
    from media m
        join media_tags_map mtm on ( m.media_id = mtm.media_id )
    where
        mtm.tags_id = ?
SQL

    if ( $media_id )
    {
        my $medium = $db->find_by_id( 'media', $media_id );
        push( @{ $media }, $medium );
    }

    die( "no media found for media_id $media_id / tags_id_media $tags_id_media" ) unless ( @{ $media } );

    return $media;
}

sub main
{
    my $p = {};

    Getopt::Long::GetOptions(
        $p,                  "start_url=s", "story_url_pattern=s", "page_url_pattern=s",
        "content_pattern=s", "media_id=i",  "start_date=s",        "end_date=s",
        "max_pages=i",       "debug!",      "dry_run!",            "feed_url=s",
        "import_module=s",   "tags_id_media=i"
    ) || return;

    if ( !$p->{ import_module } )
    {
        die( "usage: $0 ---media_id <id> --import_module <import module>" );
    }

    my $import_module = $_import_module_lookup->{ lc( $p-{ import_module } ) } ||
        die( "Unknown import_module: '$p->{ import_module }'" );

    delete( $p->{ import_module } );

    $p->{ db } = MediaWords::DB::connect_to_db;

    my $media = get_media_from_options( $p->{ db }, $p->{ media_id }, $p->{ tags_id_media }, $import_module );

    for my $medium ( @{ $media } )
    {
        $p->{ media_id } = $medium->{ media_id };
        eval( '${ import_module }->new( $p )->scrape_stories()' );
        die( $@ ) if ( $@ );
    }
}

main();
