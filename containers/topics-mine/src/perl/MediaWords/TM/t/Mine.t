use strict;
use warnings;

use Test::Deep;
use Test::More tests => 3;

use MediaWords::CommonLibs;

use MediaWords::Test::DB;
use MediaWords::Test::DB::Create;
use MediaWords::TM::Mine;
use MediaWords::TM::Stories;

my $_topic_stories_medium_count = 0;

sub add_test_topic_stories($$$$)
{
    my ( $db, $topic, $num_stories, $label ) = @_;

    my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, "$label  " . $_topic_stories_medium_count++ );
    my $feed = MediaWords::Test::DB::Create::create_test_feed( $db, $label, $medium );

    for my $i ( 1 .. $num_stories )
    {
        my $story = MediaWords::Test::DB::Create::create_test_story( $db, "$label $i", $feed );
        MediaWords::TM::Stories::add_to_topic_stories( $db, $story, $topic );
    }
}

sub test_die_if_max_stories_exceeded($)
{
    my ( $db ) = @_;

    my $label = "test_die_if_max_stories_exceeded";

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, $label );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { max_stories => 0 } );

    add_test_topic_stories( $db, $topic, 101, $label );

    eval { MediaWords::TM::Mine::die_if_max_stories_exceeded( $db, $topic ); };
    ok( $@, "$label adding 101 stories to 0 max_stories topic generates error" );

    $db->query( "delete from topic_stories where topics_id = ?", $topic->{ topics_id } );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { max_stories => 100 } );

    add_test_topic_stories( $db, $topic, 99, $label );
    eval { MediaWords::TM::Mine::die_if_max_stories_exceeded( $db, $topic ); };
    ok( !$@, "$label adding 999 stories to a 100 max_stories does not generate an error: $@" );

    add_test_topic_stories( $db, $topic, 102, $label );
    eval { MediaWords::TM::Mine::die_if_max_stories_exceeded( $db, $topic ); };
    ok( $@, "$label adding 2001 stories to a 100 max_stories generates an error" );
}

sub test_mine($)
{
    my ( $db ) = @_;

    test_die_if_max_stories_exceeded( $db );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_mine );
}

main();
