use strict;
use warnings;

use Test::Deep;
use Test::More tests => 10;

use MediaWords::CommonLibs;

use MediaWords::Test::DB;
use MediaWords::TM::Mine;

sub test_postgres_regex_match($)
{
    my $db = shift;

    my $regex = '(?: [[:<:]]alt-right | [[:<:]]alt[[:space:]]+right | [[:<:]]alternative[[:space:]]+right )';

    {
        # Match
        my $strings = [ 'This is a string describing alt-right and something else.' ];
        ok( MediaWords::TM::Mine::postgres_regex_match( $db, $strings, $regex ) );
    }

    {
        # No match
        my $strings = [ 'This is a string describing just something else.' ];
        ok( !MediaWords::TM::Mine::postgres_regex_match( $db, $strings, $regex ) );
    }

    {
        # One matching string
        my $strings = [
            'This is a string describing something else.',    #
            'This is a string describing alt-right.',         #
        ];
        ok( MediaWords::TM::Mine::postgres_regex_match( $db, $strings, $regex ) );
    }

    {
        # Two non-matching strings
        my $strings = [
            'This is a string describing something else.',          #
            'This is a string describing something else again.',    #
        ];
        ok( !MediaWords::TM::Mine::postgres_regex_match( $db, $strings, $regex ) );
    }

    {
        my $strings = [ ( 'x' x ( 8 * 1024 * 1024 ) ) . 'MATCH' ];
        ok( !MediaWords::TM::Mine::postgres_regex_match( $db, $strings, 'MATCH' ) );
    }

    {
        my $strings = [ 'MATCH' . ( 'x' x ( 8 * 1024 * 1024 ) ) ];
        ok( MediaWords::TM::Mine::postgres_regex_match( $db, $strings, 'MATCH' ) );
    }

    {
        # make sure we just fail and don't crash on null char
        my $strings = [ "MATCH\x00FOO" ];
        ok( !MediaWords::TM::Mine::postgres_regex_match( $db, $strings, 'MATCH' ) );
    }

}

my $_topic_stories_medium_count = 0;

sub add_test_topic_stories($$$$)
{
    my ( $db, $topic, $num_stories, $label ) = @_;

    my $medium = MediaWords::Test::DB::create_test_medium( $db, "$label  " . $_topic_stories_medium_count++ );
    my $feed = MediaWords::Test::DB::create_test_feed( $db, $label, $medium );

    for my $i ( 1 .. $num_stories )
    {
        my $story = MediaWords::Test::DB::create_test_story( $db, "$label $i", $feed );
        MediaWords::TM::Mine::add_to_topic_stories( $db, $topic, $story, 1, 'f', 1 );
    }
}

sub test_die_if_max_stories_exceeded($)
{
    my ( $db ) = @_;

    my $label = "test_die_if_max_stories_exceeded";

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { max_stories => 0 } );

    eval { add_test_topic_stories( $db, $topic, 1001, $label ) };
    ok( $@, "$label adding 1001 stories to 0 max_stories topic generates error" );

    $db->query( "delete from topic_stories where topics_id = ?", $topic->{ topics_id } );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { max_stories => 1000 } );

    eval { add_test_topic_stories( $db, $topic, 999, $label ) };
    ok( !$@, "$label adding 999 stories to a 1000 max_stories does not generate an error: $@" );

    eval { add_test_topic_stories( $db, $topic, 1002, $label ) };
    ok( $@, "$label adding 2001 stories to a 1000 max_stories generates an error" );
}

sub test_mine($)
{
    my ( $db ) = @_;

    test_postgres_regex_match( $db );
    test_die_if_max_stories_exceeded( $db );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_mine );
}

main();
