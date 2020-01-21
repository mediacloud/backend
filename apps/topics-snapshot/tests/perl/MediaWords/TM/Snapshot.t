use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::Job::TM::SnapshotTopic;
use MediaWords::TM::Stories;
use MediaWords::Test::DB::Create;
use MediaWords::Util::ParseJSON;

my $NUM_STORIES = 100;

sub add_test_topic_stories($$$$)
{
    my ( $db, $topic, $num_stories, $label ) = @_;

    my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, $label );
    my $feed = MediaWords::Test::DB::Create::create_test_feed( $db, $label, $medium );

    for my $i ( 1 .. $num_stories )
    {
        my $story = MediaWords::Test::DB::Create::create_test_story( $db, "$label $i", $feed );
        MediaWords::TM::Stories::add_to_topic_stories( $db, $story, $topic );
        $db->update_by_id( 'stories', $story->{ stories_id }, { publish_date => $topic->{ start_date } } );
    }
}

sub add_test_seed_query($$)
{
    my ( $db, $topic ) = @_;

    my $tsq = {
        source => 'csv',
        platform => 'generic_post',
        topics_id => $topic->{ topics_id },
        query => 'test query'
    };
    return $db->create( 'topic_seed_queries', $tsq );
}

sub test_snapshot($)
{
    my ( $db ) = @_;

    srand( 3 );

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'test snapshot' );

    my $topics_id = $topic->{ topics_id };

    add_test_topic_stories( $db, $topic, $NUM_STORIES, 'test snapshot' );

    my $expected_seed_query = add_test_seed_query( $db, $topic );

    my $stories = $db->query( "select * from stories" )->hashes;
    for my $story ( @{ $stories } )
    {
        my $ref_story = $db->query( "select * from stories where stories_id = ?", $story->{ stories_id } + 1 )->hash;
        next unless $ref_story;

        my $topic_link = {
            topics_id => $topics_id,
            stories_id => $story->{ stories_id },
            url => $ref_story->{ url },
            ref_stories_id => $ref_story->{ stories_id },
            link_spidered => 't'
        };
        $db->create( 'topic_links', $topic_link );
    }

    MediaWords::Job::TM::SnapshotTopic->run( { topics_id => $topics_id } );

    my $got_snapshot = $db->query( "select * from snapshots where topics_id = ?", $topic->{ topics_id } )->hash;

    ok( $got_snapshot, "snapshot exists" );
    is( $got_snapshot->{ topics_id }, $topics_id, "snapshot topics_id" );
    is( $got_snapshot->{ state }, 'completed', "snapshot state" );
    is( substr( $got_snapshot->{ start_date }, 0, 10), $topic->{ start_date }, "snapshot start_date" );
    is( substr( $got_snapshot->{ end_date }, 0, 10), $topic->{ end_date }, "snapshot end_date" );

    my $seed_queries = $got_snapshot->{ seed_queries };
    ok( $seed_queries, "snapshot seed_queries present" );

    is( $seed_queries->{ topic }->{ solr_seed_query }, $topic->{ solr_seed_query } );

    my $got_topic_seed_queries = $seed_queries->{ topic_seed_queries };
    is( scalar( @{ $got_topic_seed_queries } ), 1, "number of topic seed queries" );

    for my $field ( qw/platform source topics_id query/ )
    {
        is( $got_topic_seed_queries->[ 0 ]->{ $field }, $expected_seed_query->{ $field }, "tsq $field" );
    }

    my $snapshots_id = $got_snapshot->{ snapshots_id };

    my $snapshot_stories = $db->query( "select * from snap.stories where snapshots_id = ?", $snapshots_id )->hashes;
    is( scalar( @{ $snapshot_stories } ), $NUM_STORIES , "snapshot stories" );

    my $timespan = $db->query( <<SQL, $snapshots_id )->hash;
select * from timespans where snapshots_id = ? and period = 'overall'
SQL

    ok( $timespan, "overall timespan created" );

    my $timespans_id = $timespan->{ timespans_id };

    my $slc = $db->query( "select * from snap.story_link_counts where timespans_id = ?", $timespans_id )->hashes;

    is( scalar( @{ $slc } ), $NUM_STORIES, "story link counts" );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_snapshot( $db );

    done_testing();
}

main();
