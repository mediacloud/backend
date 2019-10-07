use strict;
use warnings;

use Test::Deep;
use Test::More tests => 3;

use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Test::DB::Create;
use MediaWords::TM::Mine;

use FindBin;
use lib $FindBin::Bin;

use AddTestTopicStories;

sub test_die_if_max_stories_exceeded($)
{
    my ( $db ) = @_;

    my $label = "test_die_if_max_stories_exceeded";

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, $label );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { max_stories => 0 } );

    AddTestTopicStories::add_test_topic_stories( $db, $topic, 101, $label );

    eval { MediaWords::TM::Mine::die_if_max_stories_exceeded( $db, $topic ); };
    ok( $@, "$label adding 101 stories to 0 max_stories topic generates error" );

    $db->query( "delete from topic_stories where topics_id = ?", $topic->{ topics_id } );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { max_stories => 100 } );

    AddTestTopicStories::add_test_topic_stories( $db, $topic, 99, $label );
    eval { MediaWords::TM::Mine::die_if_max_stories_exceeded( $db, $topic ); };
    ok( !$@, "$label adding 999 stories to a 100 max_stories does not generate an error: $@" );

    AddTestTopicStories::add_test_topic_stories( $db, $topic, 102, $label );
    eval { MediaWords::TM::Mine::die_if_max_stories_exceeded( $db, $topic ); };
    ok( $@, "$label adding 2001 stories to a 100 max_stories generates an error" );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_die_if_max_stories_exceeded( $db );
}

main();
