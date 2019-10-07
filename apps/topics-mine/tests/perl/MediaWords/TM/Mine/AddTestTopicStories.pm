package AddTestTopicStories;

use strict;
use warnings;

use MediaWords::CommonLibs;
use MediaWords::Test::DB::Create;
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
        $db->update_by_id( 'stories', $story->{ stories_id }, { publish_date => $topic->{ start_date } } );
    }
}

1;
