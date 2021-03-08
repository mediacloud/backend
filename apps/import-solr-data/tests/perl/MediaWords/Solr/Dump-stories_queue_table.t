use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::Solr::Dump;
use MediaWords::Test::Solr;

sub test_import_stories_queue_table($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::Solr::create_test_story_stack_for_indexing(
        $db,
        {
            medium_1 => { feed_1 => [ map { "story_$_" } ( 1 .. 5 ) ] },
            medium_2 => { feed_2 => [ map { "story_$_" } ( 6 .. 15 ) ] },
            medium_3 => { feed_3 => [ map { "story_$_" } ( 16 .. 30 ) ] },
        }
    );

    my $test_stories = $db->query( "select * from stories order by md5( stories_id::text )" )->hashes;

    $db->query( "create table test_stories_queue ( stories_id int )" );

    MediaWords::Test::Solr::queue_all_stories( $db, 'test_stories_queue' );

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

    is( MediaWords::Solr::get_solr_num_found( $db, { q => '*:*' } ), $test_stories_size, "stories after queue import" );

    my ( $post_num_solr_imports )          = $db->query( "select count(*) from solr_imports" )->flat;
    my ( $post_num_solr_imported_stories ) = $db->query( "select count(*) from solr_imported_stories" )->flat;

    is( $pre_num_solr_imports, $post_num_solr_imports, "solr_imports rows with skip_logging" );
    is( $pre_num_solr_imported_stories, $post_num_solr_imported_stories,
        "solr_imported_stories rows with skip_logging" );

    my $story = pop( @{ $test_stories } );
    MediaWords::Test::Solr::test_story_query( $db, '*:*', $story, 'alternate stories queue table' );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_import_stories_queue_table( $db );

    done_testing();
}

main();
