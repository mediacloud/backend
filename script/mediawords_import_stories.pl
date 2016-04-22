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

sub get_media_from_options
{
    my ( $db, $media_id, $tags_id_media ) = @_;

    die( "must specify --media_id or --tags_id_media" ) unless ( $media_id || $tags_id_media );

    $media_id      ||= 0;
    $tags_id_media ||= 0;

    my $media = $db->query( <<SQL, $tags_id_media )->hashes;
select m.*
    from media m
        join media_tags_map mtm on ( m.media_id = mtm.media_id )
    where
        mtm.tags_id = ?
SQL

    my $medium = $db->find_by_id( 'media', $media_id );

    push( @{ $media }, $medium );

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

    $p->{ db } = MediaWords::DB::connect_to_db;

    my $media = get_media_from_options( $p->{ db }, $p->{ media_id }, $p->{ tags_id_media } );

    my $import_module = $p->{ import_module };
    delete( $p->{ import_module } );

    for my $medium ( @{ $media } )
    {
        $p->{ media_id } = $medium->{ media_id };
        if ( $import_module eq 'feedly' )
        {
            MediaWords::ImportStories::Feedly->new( $p )->scrape_stories();
        }
        elsif ( $import_module eq 'scrapehtml' )
        {
            MediaWords::ImportStories::ScrapeStories->new( $p )->scrape_stories();
        }
        else
        {
            die( "Unknown module '$p->{ import_module }'" );
        }
    }
}

main();
