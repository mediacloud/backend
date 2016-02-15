#!/usr/bin/env perl

#
# for every story in scratch.ap_queue, set ap_syndication and delete the story from the queue
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";

use MediaWords::CommonLibs;
use MediaWords::DBI::Stories::AP;

sub attach_downloads_to_stories
{
    my ( $db, $stories ) = @_;

    my $stories_id_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my $downloads = $db->query( <<SQL )->hashes;
select * from downloads
    where stories_id in ( $stories_id_list )
    order by downloads_id;
SQL

    my $downloads_lookup = {};
    for my $download ( @{ $downloads } )
    {
        next if ( $downloads_lookup->{ $download->{ stories_id } } );

        $downloads_lookup->{ $download->{ stories_id } } = $download;
    }

    map { $_->{ download } = $downloads_lookup->{ $_->{ stories_id } } } @{ $stories };
}

sub get_stories_from_queue
{
    my ( $db, $block_size ) = @_;

    my $stories = $db->query( <<SQL )->hashes;
select * from stories s join scratch.ap_queue q on ( s.stories_id = q.stories_id ) limit $block_size
SQL

    attach_downloads_to_stories( $db, $stories );

    return $stories;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $block_size = 10;

    my $stories_processed = 0;
    while ( my $stories = get_stories_from_queue( $db, $block_size ) )
    {
        say STDERR "updating " . ( ++$stories_processed * $block_size );
        for my $story ( @{ $stories } )
        {
            MediaWords::StoryVectors::_update_ap_syndicated( $db, $story, $story->{ language } );
        }

        my $ids_list = join( ',', map { $_->{ stories_id } } @{ $stories } );
        $db->query( "delete from scratch.ap_queue where stories_id in ( $ids_list )" );
    }
}

main();
