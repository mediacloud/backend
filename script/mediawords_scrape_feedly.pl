#!/usr/bin/env perl

# scrape stories from feedly for the specified feeds, or process all unscraped feeds one by one

package script::mediawords_scrape_feedly;

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CommonLibs;
use MediaWords::ImportStories::Feedly;

my $_feedly_import_module = 'MediaWords::ImportStories::Feedly';

sub get_media_from_tags_id
{
    my ( $db, $tags_id ) = @_;

    my $media = $db->query( <<SQL, $tags_id )->hashes;
select m.*
    from media m
        join media_tags_map mtm on ( m.media_id = mtm.media_id )
    where
        mtm.tags_id = ? and
        exists ( select 1 from feedly_unscraped_feeds f where f.media_id = m.media_id )
SQL

    return $media;
}

sub feedly_import
{
    my ( $db, $options ) = @_;

    DEBUG( sub { "feedly_import: " . Dumper( $options ) } );

    my $import = MediaWords::ImportStories::Feedly->new( { db => $db, %{ $options } } );

    $import->scrape_stories();

    for my $feeds_id ( @{ $import->scraped_feeds_ids } )
    {
        $db->create( 'scraped_feeds', { feeds_id => $feeds_id, import_module => $_feedly_import_module } );
    }
}

sub get_unscraped_medium
{
    my ( $db ) = @_;

    my $medium = $db->query( <<SQL )->hash;
select m.* from media m join feedly_unscraped_feeds fuf on ( fuf.media_id = m.media_id ) limit 1;
SQL
}

sub main
{
    my $opt = {};

    Getopt::Long::GetOptions( $opt, "tags_id=i", "feeds_id=i", "media_id=i", "all!" ) || return;

    my $db = MediaWords::DB::connect_to_db;

    if ( my $tags_id = $opt->{ tags_id } )
    {
        my $media     = get_media_from_tags_id( $db, $tags_id );
        my $i         = 0;
        my $num_media = scalar( @{ $media } );
        for my $medium ( @{ $media } )
        {
            DEBUG( "importing tags_id: $tags_id [" . ++$i . "/$num_media]" );
            feedly_import( $db, { media_id => $medium->{ media_id } } );
        }
    }

    if ( my $media_id = $opt->{ media_id } )
    {
        feedly_import( $db, { media_id => $media_id } );
    }

    if ( my $feeds_id = $opt->{ feeds_id } )
    {
        my $feed = $db->find_by_id( 'feeds', $feeds_id ) || LOGIDE( "Unable to find feed: $feeds_id" );
        feedly_import( $db, { feeds_id => $feeds_id, media_id => $feed->{ media_id } } );
    }

    if ( $opt->{ all } )
    {
        DEBUG( "importing ALL" );
        while ( my $medium = get_unscraped_medium( $db ) )
        {
            feedly_import( $db, { media_id => $medium->{ media_id } } );
            return;
        }
    }

}

main();
