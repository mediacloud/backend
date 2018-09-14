#!/usr/bin/env perl

# test dumping and importing of data for solr

use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::Solr::Query;
use MediaWords::Solr::Dump;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;
use MediaWords::Util::Tags;

sub get_solr_date_clause
{
    my ( $sql_date ) = @_;

    if ( !( $sql_date =~ /(\d+)\-(\d+)\-(\d+)/ ) )
    {
        die( "unable to parse sql date: '$sql_date'" );
    }

    my ( $year, $month, $day ) = ( $1, $2, $3 );

    return "publish_day:$year-$month-${day}T00\\:00\\:00Z";
}

sub test_import
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::Solr::create_indexed_test_story_stack(
        $db,
        {
            medium_1 => { feed_1 => [ map { "story_$_" } ( 1 .. 5 ) ] },
            medium_2 => { feed_2 => [ map { "story_$_" } ( 6 .. 15 ) ] },
            medium_3 => { feed_3 => [ map { "story_$_" } ( 16 .. 30 ) ] },
        }
    );

    my $test_stories = $db->query( "select * from stories order by md5( stories_id::text )" )->hashes;

    {
        my $got_num_solr_stories = MediaWords::Solr::Query::get_num_found( $db, { q => '*:*' } );
        is( $got_num_solr_stories, scalar( @{ $test_stories } ), "total number of stories in solr" );

        my $solr_import = $db->query( "select * from solr_imports" )->hash;
        ok( $solr_import->{ full_import }, "solr_imports row created with full=true" );

        my ( $num_solr_imported_stories ) = $db->query( "select count(*) from solr_imported_stories" )->flat;
        is( $num_solr_imported_stories, scalar( @{ $test_stories } ), "number of rows in solr_imported_stories" );
    }

    {
        my $story = pop( @{ $test_stories } );
        test_story_query( $db, "media_id:$story->{ media_id }", $story, 'media_id' );
    }

    {
        my $story = pop( @{ $test_stories } );
        my $title_clause = 'title:(' . join( ' and ', split( /\W/, $story->{ title } ) ) . ')';
        test_story_query( $db, $title_clause, $story, "title" );
    }

    {
        my $story       = pop( @{ $test_stories } );
        my $date_clause = get_solr_date_clause( $story->{ publish_date } );
        test_story_query( $db, $date_clause, $story, "publish_date" );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $text ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select string_agg( sentence, ' ' order by sentence_number ) from story_sentences where stories_id = ?
SQL

        my $words = [ grep { $_ } ( split( /\W/, $text ) )[ 0 .. 10 ] ];
        my $text_clause = 'text: (' . join( ' and ', @{ $words } ) . ')';

        test_story_query( $db, $text_clause, $story, 'text clause' );
    }

    {
        my $story = pop( @{ $test_stories } );
        test_story_query( $db, "language:$story->{ language }", $story, 'language' );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $tags_id ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select tags_id from stories_tags_map where stories_id = ?
SQL

        test_story_query( $db, "tags_id_stories:$tags_id", $story, 'tags_id_stories' );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $processed_stories_id ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select processed_stories_id from processed_stories where stories_id = ?
SQL
        test_story_query( $db, "processed_stories_id:$processed_stories_id", $story, 'processed_stories_id' );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $timespans_id ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select timespans_id from snap.story_link_counts where stories_id = ? limit 1
SQL
        test_story_query( $db, "timespans_id:$timespans_id", $story, 'timespans_id' );
    }

    {
        # test that import grabs updated story
        my $story = pop( @{ $test_stories } );
        $db->query( "update stories set language = 'up' where stories_id = ?", $story->{ stories_id } );
        $db->commit();

        MediaWords::Solr::Dump::import_data( $db, { empty_queue => 1, throttle => 0 } );
        test_story_query( $db, "language:up", $story, 'import updated story' );
    }

    {
        # test that processed_stories update queues import
        my $story = pop( @{ $test_stories } );
        $db->create( 'processed_stories', { stories_id => $story->{ stories_id } } );
        my $solr_import_story = $db->query( <<SQL, $story->{ stories_id } )->hash();
select * from solr_import_stories where stories_id = ?
SQL
        ok( $solr_import_story, "queue story from processed_stories insert" );
    }

    {
        # test that stories_tags_map update queues import
        my $story = pop( @{ $test_stories } );
        my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'import:test' );
        $db->query( <<SQL, $story->{ stories_id }, $tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )       
SQL

        my $solr_import_story = $db->query( <<SQL, $story->{ stories_id } )->hash();
select * from solr_import_stories where stories_id = ?
SQL
        ok( $solr_import_story, "queue story from stories_tags_map insert" );
    }

    {
        # test delete_all, queue_all_stories, and stories_queue_table option of import_data
        MediaWords::Solr::Dump::delete_all_stories( $db );
        is( MediaWords::Solr::Query::get_num_found( $db, { q => '*:*' } ), 0, "stories after deleting" );

        $db->query( "create table test_stories_queue ( stories_id int )" );

        MediaWords::Solr::Dump::queue_all_stories( $db, 'test_stories_queue' );

        my ( $test_queue_size )   = $db->query( "select count(*) from test_stories_queue" )->flat;
        my ( $test_stories_size ) = $db->query( "select count(*) from stories" )->flat;
        is( $test_queue_size, $test_stories_size, "test queue size" );

        my ( $pre_num_solr_imports )          = $db->query( "select count(*) from solr_imports" )->flat;
        my ( $pre_num_solr_imported_stories ) = $db->query( "select count(*) from solr_imported_stories" )->flat;

        MediaWords::Solr::Dump::import_data(
            $db,
            {
                queue_only          => 1,
                stories_queue_table => 'test_stories_queue',
                skip_logging        => 1,
                throttle            => 0,
            }
        );

        is( MediaWords::Solr::Query::get_num_found( $db, { q => '*:*' } ), $test_stories_size,
            "stories after queue import" );

        my ( $post_num_solr_imports )          = $db->query( "select count(*) from solr_imports" )->flat;
        my ( $post_num_solr_imported_stories ) = $db->query( "select count(*) from solr_imported_stories" )->flat;

        is( $pre_num_solr_imports, $post_num_solr_imports, "solr_imports rows with skip_logging" );
        is( $pre_num_solr_imported_stories, $post_num_solr_imported_stories,
            "solr_imported_stories rows with skip_logging" );

        my $story = pop( @{ $test_stories } );
        test_story_query( $db, '*:*', $story, 'alternate stories queue table' );
    }

    {
        # test threaded import
        MediaWords::Solr::Dump::delete_all_stories( $db );
        is( MediaWords::Solr::Query::get_num_found( $db, { q => '*:*' } ), 0, "stories after deleting" );

        MediaWords::Solr::Dump::queue_all_stories( $db );

        MediaWords::Solr::Dump::import_data( $db, { full => 1, jobs => 3, throttle => 0 } );

        $db = MediaWords::DB::connect_to_db();

        my ( $test_stories_size ) = $db->query( "select count(*) from stories" )->flat;
        is( MediaWords::Solr::Query::get_num_found( $db, { q => '*:*' } ), $test_stories_size, "stories threaded import" );

        my $story = pop( @{ $test_stories } );
        test_story_query( $db, "*:*", $story );
    }

}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_import, [ 'solr_standalone' ] );

    done_testing();
}

main();
