#!/usr/bin/env perl

# find all media sources that share a feed with another media source.  for each such
# match, find the media source with the fewer feeds. for that smaller media source, mark
# each feed that is also present in the larger media source as a duplicate feed.  
# this is helpful for letting the db know which feeds to ignore when it does not want to 
# include duplicate stories, for example in controversy mapping.

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;

# mark each feed that is in both main_medium and dup_medium as a duplicate feed for dup_medium
sub mark_duplicate_feeds
{
    my ( $db, $main_media_id, $dup_media_id ) = @_;
    
    my $dup_feeds = $db->query( "select * from feeds where media_id = ?", $dup_media_id )->hashes;
    my $main_feeds = $db->query( "select * from feeds where media_id = ?", $main_media_id )->hashes;
    
    my $main_medium_feed_map = {};
    map { $main_medium_feed_map->{ lc( $_->{ url } ) } = 1 } @{ $main_feeds };
    
    for my $dup_feed ( @{ $dup_feeds } )
    {
        next unless ( $main_medium_feed_map->{ lc( $dup_feed->{ url } ) } );

        print STDERR "$dup_feed->{ url } <- dup media $main_media_id\n";
        
        $db->query( "update feeds set dup_media_id = ? where feeds_id = ?", $main_media_id, $dup_feed->{ feeds_id } );
    }
}

# given two media that share an identical feed and mark the one with
# fewer feeds as a duplicate of the first
sub mark_duplicate_media
{
    my ( $db, $media_id_a, $media_id_b ) = @_;
        
    my ( $feed_count_a ) = $db->query( "select count(*) from feeds where media_id = ?", $media_id_a )->flat;
    my ( $feed_count_b ) = $db->query( "select count(*) from feeds where media_id = ?", $media_id_b )->flat;
    
    ( $feed_count_a > $feed_count_b ) ? 
        mark_duplicate_feeds( $db, $media_id_a, $media_id_b ) : mark_duplicate_feeds( $db, $media_id_b, $media_id_a );
}

sub main 
{
    my $db = MediaWords::DB::connect_to_db;
    
    my $duplicate_media_pairs = $db->query( <<END )->hashes;
select distinct ma.media_id media_id_a, mb.media_id media_id_b
    from media ma, feeds fa, media mb, feeds fb 
    where ma.media_id = fa.media_id and mb.media_id = fb.media_id and lower( fa.url )  = lower ( fb.url ) and 
        fa.media_id < fb.media_id
END

    map { mark_duplicate_media( $db, $_->{ media_id_a }, $_->{ media_id_b } ) } @{ $duplicate_media_pairs };    
}

main();