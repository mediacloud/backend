#!/usr/bin/env perl

# test dumping and importing of data for solr

use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::Solr::Dump;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;
use MediaWords::Util::Tags;

sub test_query
{
    my ( $db, $q, $expected_story ) = @_;

    my $expected_stories_id = $expected_story->{ stories_id };

    my $r = MediaWords::Solr::query( $db, { q => "$q and stories_id:$expected_stories_id", rows => 1_000_000 } );

    my $docs = $r->{ response }->{ docs };

    die( "no response.docs found in solr results: " . Dumper( $r ) ) unless ( $docs );

    my $got_stories_ids = [ map { $_->{ stories_id } } @{ $docs } ];

    is_deeply( $got_stories_ids, [ $expected_stories_id ], "test query $q" );

}

sub get_solr_date_clause
{
    my ( $sql_date ) = @_;

    if ( !( $sql_date =~ /(\d+)\-(\d+)\-(\d+)/ ) )
    {
        die( "unable to parse sql date: '$sql_date'" );
    }

    my ( $year, $month, $day ) = ( $1, $2, $3 );

    my $date_range = "[$year-$month-${day}T00:00:00Z TO $year-$month-${day}T23:59:59Z]";
    return "publish_date:$date_range and publish_day:$date_range";
}

sub add_story_tags
{
    my ( $db, $stories ) = @_;

    my $tags     = [];
    my $num_tags = 5;

    for my $i ( 1 .. $num_tags )
    {
        push( @{ $tags }, MediaWords::Util::Tags::lookup_or_create_tag( $db, "test:test_$i" ) );
    }

    for my $story ( @{ $stories } )
    {
        my $tag = pop( @{ $tags } );
        unshift( @{ $tags }, $tag );
        $db->query( <<SQL, $story->{ stories_id }, $tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
SQL
    }
}

sub test_import
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack(
        $db,
        {
            medium_1 => { feed_1 => [ map { "story_$_" } ( 1 .. 5 ) ] },
            medium_2 => { feed_2 => [ map { "story_$_" } ( 6 .. 15 ) ] },
            medium_3 => { feed_3 => [ map { "story_$_" } ( 16 .. 30 ) ] },
        }
    );
    MediaWords::Test::DB::add_content_to_test_story_stack( $db, $media );

    # return a stack of randomly but consistently ordered stories that we can pop off one at a time
    # for a series of solr query tests
    my $test_stories = $db->query( "select * from stories order by md5( stories_id::text )" )->hashes;

    # add tags to stories so that we can test tags_id_media and tags_id_storie
    add_story_tags( $db, $test_stories );

    MediaWords::Test::Solr::setup_test_index( $db );

    my $got_num_solr_stories = MediaWords::Solr::get_num_found( $db, { q => '*:*' } );
    is( $got_num_solr_stories, 30, "total number of stories in solr" );

    {
        my $story = pop( @{ $test_stories } );
        test_query( $db, "media_id:$story->{ media_id }", $story );
    }

    {
        my $story = pop( @{ $test_stories } );
        my $title_clause = 'title:(' . join( ' and ', split( /\W/, $story->{ title } ) ) . ')';
        test_query( $db, $title_clause, $story, "title" );
    }

    {
        my $story       = pop( @{ $test_stories } );
        my $date_clause = get_solr_date_clause( $story->{ publish_date } );
        test_query( $db, $date_clause, $story, "publish_date" );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $text ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select string_agg( sentence, ' ' order by sentence_number ) from story_sentences where stories_id = ?
SQL

        my $words = [ grep { $_ } ( split( /\W/, $text ) )[ 0 .. 10 ] ];
        my $text_clause = 'text: (' . join( ' and ', @{ $words } ) . ')';

        test_query( $db, $text_clause, $story );
    }

    {
        my $story = pop( @{ $test_stories } );
        test_query( $db, "language:$story->{ language }", $story );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $tags_id ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select tags_id from stories_tags_map where stories_id = ?
SQL

        test_query( $db, "tags_id_stories:$tags_id", $story );
    }

}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_import, [ 'solr_standalone' ] );

    done_testing();
}

main();
