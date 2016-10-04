#!/usr/bin/env perl

# fix the dup_media_id field so that it always points to the one media source that should be searched via the dashboard.

package script::mediawords_fix_dump_media;

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use FileHandle;

use MediaWords::DB;

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    # media marked as dup parents
    $db->query(
        "create temporary table parent_media as select * from media where media_id in ( select dup_media_id from media )" );
    $db->query( <<SQL );
create temporary table all_media_health as
    select m.media_id, coalesce( mh.num_stories_90, 0, num_stories_90 ) num_stories_90
        from media m
            left join media_health mh using ( media_id )
SQL

    my ( $num_dup_media_parents ) = $db->query( "select count(*) from parent_media" )->flat;
    say( "number of media marked as dup parents: $num_dup_media_parents" );

    $db->query( <<SQL );
create temporary table biggest_child_media as
    select * from (
        select
                m.media_id,
                m.dup_media_id,
                mh.num_stories_90,
                row_number() over ( partition by m.dup_media_id order by num_stories_90 desc ) r
            from media m
                join all_media_health mh using ( media_id )
            where
                m.dup_media_id is not null
        ) q
        where r = 1
SQL

    $db->query( <<SQL );
create view parent_and_child_media as
    select
        pm.media_id parent_media_id,
        pmh.num_stories_90 parent_num_stories_90,
        dm.media_id child_media_id,
        dmh.num_stories_90 child_num_stories_90
    from parent_media pm
        join all_media_health pmh using ( media_id )
        join biggest_child_media dm on ( pm.media_id = dm.dup_media_id )
        join all_media_health dmh on ( dm.media_id = dmh.media_id )
SQL

    $db->query( <<SQL );
create temporary table public_set_media as
    with public_tags as ( select * from tags where show_on_media )
    select * from media m
        where m.media_id in (
            select media_id
                from media_tags_map mtm
                    join public_tags t using ( tags_id )
            )
SQL

    # public set media with the most stories

    $db->query( <<SQL );
create temporary table public_set_media_with_most_stories as
    select * from media where media_id in (
        select parent_media_id from parent_and_child_media where
            parent_media_id in ( select media_id from public_set_media ) and
            parent_num_stories_90 >= ( child_num_stories_90 * 0.90 )
    )
SQL

    my ( $num_public_media_most_stories ) = $db->query( "select count(*) from public_set_media_with_most_stories" )->flat;

    $db->query( "delete from parent_media where media_id in ( select media_id from public_set_media_with_most_stories )" );
    say( "remove public set media with the most stories: $num_public_media_most_stories" );

    ( $num_dup_media_parents ) = $db->query( "select count(*) from parent_media" )->flat;
    say( "remaining dup parents: $num_dup_media_parents" );

    # media with the most stories and no public set dups

    $db->query( <<SQL );
create temporary table no_public_dup_media_with_most_stories as
    select * from media where media_id in (
        select parent_media_id from parent_and_child_media where
            child_media_id not in ( select media_id from public_set_media ) and
            parent_num_stories_90 >= ( child_num_stories_90 * 0.90 )
    )
SQL

    my ( $num_no_public_dup_media_most_stories ) =
      $db->query( "select count(*) from no_public_dup_media_with_most_stories" )->flat;
    say( "remove media with the most stories and no public set dups: $num_no_public_dup_media_most_stories" );

    $db->query(
        "delete from parent_media where media_id in ( select media_id from no_public_dup_media_with_most_stories )" );

    ( $num_dup_media_parents ) = $db->query( "select count(*) from parent_media" )->flat;
    say( "remaining dup parents: $num_dup_media_parents" );

    # public set child with more stories

    $db->query( <<SQL );
create temporary table public_set_child_media_with_most_stories as
    select * from media where media_id in (
        select child_media_id from parent_and_child_media
            where child_media_id in ( select media_id from public_set_media ) and
            child_num_stories_90 >= ( parent_num_stories_90 * 0.90 )
    )
SQL

    my ( $num_public_set_child_media_with_most_stories ) =
      $db->query( "select count(*) from public_set_child_media_with_most_stories" )->flat;
    say( "remove media with a public set child with more stories : $num_public_set_child_media_with_most_stories" );

    $db->query(
        "delete from parent_media where media_id in ( select dup_media_id from public_set_child_media_with_most_stories )" );

    ( $num_dup_media_parents ) = $db->query( "select count(*) from parent_media" )->flat;
    say( "remaining dup parents: $num_dup_media_parents" );

    # media with a child with more stories, no public set parent

    $db->query( <<SQL );
create temporary table no_public_parent_child_media_with_most_stories as
    select * from media where media_id in (
        select child_media_id from parent_and_child_media
            where parent_media_id not in ( select media_id from public_set_media ) and
            child_num_stories_90 >= ( parent_num_stories_90 * 0.90 )
    )
SQL

    my ( $num_no_public_parent_child_media_with_most_stories ) =
      $db->query( "select count(*) from no_public_parent_child_media_with_most_stories" )->flat;
    say(
"remove media with a child with more stories, no public set parent : $num_no_public_parent_child_media_with_most_stories"
    );

    $db->query(
"delete from parent_media where media_id in ( select dup_media_id from no_public_parent_child_media_with_most_stories )"
    );

    ( $num_dup_media_parents ) = $db->query( "select count(*) from parent_media" )->flat;
    say( "remaining dup parents: $num_dup_media_parents" );

    # remaining

    my $remainder_file = 'fix_dup_media.csv';
    my $fh             = FileHandle->new( '>' . $remainder_file );
    $db->query_csv_dump( $fh, <<SQL, [], 1 );
select
        pm.media_id parent_id, pm.name parent_name, pm.url parent_url, pcm.parent_num_stories_90,
        cm.media_id child_id, cm.name child_name, cm.url child_url, pcm.child_num_stories_90
    from parent_and_child_media pcm
        join media pm on ( pcm.parent_media_id = pm.media_id )
        join media cm on ( pcm.child_media_id = cm.media_id )
SQL

    say( "wrote remaining dups to $remainder_file" );

    my $media_switches = $db->query( <<SQL )->hashes;
select sm.dup_media_id parent_media_id, pm.name parent_name, pmh.num_stories_90 parent_num_stories_90,
        sm.media_id child_media_id, cm.name child_name, cmh.num_stories_90 child_num_stories_90
    from
        ( select * from no_public_parent_child_media_with_most_stories union
            select * from public_set_child_media_with_most_stories ) sm
        join media pm on ( pm.media_id = sm.dup_media_id )
        join all_media_health pmh on ( pmh.media_id = pm.media_id )
        join media cm on ( cm.media_id = sm.media_id )
        join all_media_health cmh on ( cmh.media_id = cm.media_id )
    order by sm.dup_media_id
SQL

    say( "setting children with more stories to be parents [" . scalar( @{ $media_switches } ) . "]" );

    $db->begin();
    for my $ms ( @{ $media_switches } )
    {
        say(
"switch $ms->{ parent_media_id } $ms->{ parent_name } $ms->{ parent_num_stories_90 } / $ms->{ child_media_id } $ms->{ child_name } $ms->{ child_num_stories_90 }"
        );
        $db->query( "update media set dup_media_id = null where media_id = ?", $ms->{ child_media_id } );
        $db->query(
            "update media set dup_media_id = \$1 where dup_media_id = \$2 or media_id = \$2",
            $ms->{ child_media_id },
            $ms->{ parent_media_id }
        );
    }
    $db->commit();
}

main();
