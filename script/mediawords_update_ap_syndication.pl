#!/usr/bin/env perl

#
# for every story in scratch.ap_queue, set ap_syndication and delete the story from the queue
#

use strict;
use warnings;

use forks;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";

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
    my ( $db, $num_proc, $proc, $block_size ) = @_;

    my $stories = $db->query( <<SQL )->hashes;
select s.*
    from stories s
    where
        s.stories_id in (
            select stories_id
                from scratch.ap_queue
                where ( stories_id % $num_proc ) = $proc - 1
                order by stories_id desc limit $block_size
        )
SQL

    attach_downloads_to_stories( $db, $stories );

    return $stories;
}

sub update_stories
{
    my ( $db, $updates ) = @_;

    my $values_list = join( ',', map { "($_->{ stories_id }::int, $_->{ ap_syndicated }::boolean)" } @{ $updates } );

    $db->query( <<SQL );
insert into stories_ap_syndicated (stories_id, ap_syndicated) values $values_list;
SQL

}

sub update_ap_syndication
{
    my ( $num_proc, $proc ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    my $block_size = 1000;

    my $stories_processed = 0;
    while ( my $stories = get_stories_from_queue( $db, $num_proc, $proc, $block_size ) )
    {
        say STDERR "updating block:" . ( ++$stories_processed * $block_size );

        my $updates = [];
        for my $story ( @{ $stories } )
        {
            say STDERR "$story->{ stories_id } ...";
            my $ap_syndicated = MediaWords::DBI::Stories::AP::is_syndicated( $db, $story );

            push( @{ $updates }, { stories_id => $story->{ stories_id }, ap_syndicated => $ap_syndicated } );
        }

        update_stories( $db, $updates );

        my $ids_list = join( ',', map { $_->{ stories_id } } @{ $stories } );
        $db->query( "delete from scratch.ap_queue where stories_id in ( $ids_list )" );
    }
}

sub main
{
    my ( $num_proc ) = @ARGV;

    $num_proc //= 1;

    my $threads = [];

    for my $proc ( 1 .. $num_proc )
    {
        push( @{ $threads }, threads->create( \&update_ap_syndication, $num_proc, $proc ) );
    }

    map { $_->join() } @{ $threads };
}

main();
