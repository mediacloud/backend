use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::Solr::Dump;
use MediaWords::Test::Solr;

sub test_threaded_import($)
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

    MediaWords::Test::Solr::queue_all_stories( $db );

    MediaWords::Solr::Dump::import_data( $db, { full => 1, throttle => 0 } );

    $db = MediaWords::DB::connect_to_db();

    my ( $test_stories_size ) = $db->query( "select count(*) from stories" )->flat;
    is( MediaWords::Solr::get_num_found( $db, { q => '*:*' } ), $test_stories_size, "stories threaded import" );

    my $story = pop( @{ $test_stories } );
    MediaWords::Test::Solr::test_story_query( $db, "*:*", $story );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_threaded_import( $db );

    done_testing();
}

main();
