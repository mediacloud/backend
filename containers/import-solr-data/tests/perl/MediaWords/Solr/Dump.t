use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::Solr::Dump;
use MediaWords::Test::Solr;
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

sub test_import($)
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
        my $got_num_solr_stories = MediaWords::Solr::get_num_found( $db, { q => '*:*' } );
        is( $got_num_solr_stories, scalar( @{ $test_stories } ), "total number of stories in solr" );

        my $solr_import = $db->query( "select * from solr_imports" )->hash;
        ok( $solr_import->{ full_import }, "solr_imports row created with full=true" );

        my ( $num_solr_imported_stories ) = $db->query( "select count(*) from solr_imported_stories" )->flat;
        is( $num_solr_imported_stories, scalar( @{ $test_stories } ), "number of rows in solr_imported_stories" );
    }

    {
        my $story = pop( @{ $test_stories } );
        MediaWords::Test::Solr::test_story_query( $db, "media_id:$story->{ media_id }", $story, 'media_id' );
    }

    {
        my $story = pop( @{ $test_stories } );
        my $title_clause = 'title:(' . join( ' and ', split( /\W/, $story->{ title } ) ) . ')';
        MediaWords::Test::Solr::test_story_query( $db, $title_clause, $story, "title" );
    }

    {
        my $story       = pop( @{ $test_stories } );
        my $date_clause = get_solr_date_clause( $story->{ publish_date } );
        MediaWords::Test::Solr::test_story_query( $db, $date_clause, $story, "publish_date" );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $text ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select string_agg( sentence, ' ' order by sentence_number ) from story_sentences where stories_id = ?
SQL

        my $words = [ grep { $_ } ( split( /\W/, $text ) )[ 0 .. 10 ] ];
        my $text_clause = 'text: (' . join( ' and ', @{ $words } ) . ')';

        MediaWords::Test::Solr::test_story_query( $db, $text_clause, $story, 'text clause' );
    }

    {
        my $story = pop( @{ $test_stories } );
        MediaWords::Test::Solr::test_story_query( $db, "language:$story->{ language }", $story, 'language' );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $tags_id ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select tags_id from stories_tags_map where stories_id = ?
SQL

        MediaWords::Test::Solr::test_story_query( $db, "tags_id_stories:$tags_id", $story, 'tags_id_stories' );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $processed_stories_id ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select processed_stories_id from processed_stories where stories_id = ?
SQL
        MediaWords::Test::Solr::test_story_query( $db, "processed_stories_id:$processed_stories_id", $story, 'processed_stories_id' );
    }

    {
        my $story = pop( @{ $test_stories } );
        my ( $timespans_id ) = $db->query( <<SQL, $story->{ stories_id } )->flat;
select timespans_id from snap.story_link_counts where stories_id = ? limit 1
SQL
        MediaWords::Test::Solr::test_story_query( $db, "timespans_id:$timespans_id", $story, 'timespans_id' );
    }

    {
        # test that import grabs updated story
        my $story = pop( @{ $test_stories } );
        $db->query( "update stories set language = 'up' where stories_id = ?", $story->{ stories_id } );
        $db->commit();

        MediaWords::Solr::Dump::import_data( $db, { empty_queue => 1, throttle => 0 } );
        MediaWords::Test::Solr::test_story_query( $db, "language:up", $story, 'import updated story' );
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
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_import( $db );

    done_testing();
}

main();
