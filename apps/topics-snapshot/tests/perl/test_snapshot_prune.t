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

    $db->update_by_id( 'topics', $topics_id, { only_snapshot_engaged_stories => 't' } );

    add_test_topic_stories( $db, $topic, $NUM_STORIES, 'test snapshot' );

    my $expected_seed_query = add_test_seed_query( $db, $topic );

    my $tag_set = $db->query( "insert into tag_sets ( name ) values ( 'foo' ) returning *" )->hash;
    my $tag = $db->query( <<SQL, $tag_set->{ tag_sets_id } )->hash;
insert into tags ( tag, tag_sets_id ) values ( 'foo', ? ) returning *
SQL

    my $stories = $db->query( "select * from stories order by stories_id" )->hashes;

    my ( $outlink_story, $inlink_story, $fb_story, $post_story) = @{ $stories };

    my $topic_link = {
        topics_id => $topics_id,
        stories_id => $outlink_story->{ stories_id },
        url => $inlink_story->{ url },
        ref_stories_id => $inlink_story->{ stories_id } };
    $db->create( 'topic_links', $topic_link );

    my $ss = {
        stories_id => $fb_story->{ stories_id },
        facebook_share_count => 100 };
    $db->create( 'story_statistics', $ss );

    my $post_snapshot = {
        topics_id => $topics_id,
        snapshot_date => '2020-01-01',
        start_date => '2020-01-01',
        end_date => '2020-01-01' };
    $post_snapshot = $db->create( 'snapshots', $post_snapshot );


    my $post_timespan = {
        snapshots_id => $post_snapshot->{ snapshots_id },
        start_date => '2020-01-01',
        end_date => '2020-01-01',
        period => 'overall',
        story_count => 0,
        story_link_count => 0,
        medium_count => 0,
        medium_link_count => 0,
        post_count => 10 };
    $post_timespan = $db->create( 'timespans', $post_timespan );

    $db->query( <<SQL, $post_timespan->{ timespans_id }, $post_story->{ stories_id } );
insert into snap.story_link_counts
    ( timespans_id, stories_id, inlink_count, outlink_count, media_inlink_count, post_count )
    values ( ?, ?, 0, 0, 0, 10 )
SQL

    MediaWords::Job::TM::SnapshotTopic->run( { topics_id => $topics_id } );

    my $got_snapshot = $db->query( "select * from snapshots where topics_id = ?", $topic->{ topics_id } )->hash;

    ok( $got_snapshot, "snapshot exists" );

    my $got_stories = $db->query( <<SQL, $got_snapshot->{ snapshots_id } )->hashes;
select * from snap.stories where snapshots_id = ?
SQL


    is( scalar( @{ $got_stories } ), 3, "number of pruned stories" );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_snapshot( $db );

    done_testing();
}

main();
