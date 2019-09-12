use strict;
use warnings;

use Test::Deep;
use Test::More tests => 7;

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
        $db->update_by_id( 'stories', $story->{ stories_id } , { publish_date => $topic->{ start_date } } );
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

sub test_respider($)
{
    my ( $db ) = @_;

    my $label = "test_respider";

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, $label );

    $topic->{ start_date } = '2017-01-01';
    $topic->{ end_date } = '2018-01-01';

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id },
        { max_stories => 0, start_date => '2017-01-01', end_date => '2018-01-01' } );

    my $num_topic_stories = 101;
    add_test_topic_stories( $db, $topic, $num_topic_stories, $label );

    # no respidering without respider_stories
    $db->query( "update topic_stories set link_mined = 't'" );

    MediaWords::TM::Mine::set_stories_respidering( $db, $topic, undef );

    my ( $got_num_respider_stories ) = $db->query( "select count(*) from topic_stories where not link_mined" )->flat;
    is( $got_num_respider_stories, 0, "no stories marked for respidering" );

    # respider everything with respider_stories but no dates
    $topic->{ respider_stories } = 1;

    $db->query( "update topic_stories set link_mined = 't'" );

    MediaWords::TM::Mine::set_stories_respidering( $db, $topic, undef );

    ( $got_num_respider_stories ) = $db->query( "select count(*) from topic_stories where not link_mined" )->flat;
    is( $got_num_respider_stories, $num_topic_stories, "all stories marked for respidering" );

    # respider stories within the range of changed dates
    my $topic_update = {
        respider_stories => 't',
        respider_end_date => $topic->{ end_date },
        respider_start_date => $topic->{ start_date },
        end_date => '2019-01-01',
        start_date => '2016-01-01',
    };
    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, $topic_update );

    $db->query( "update topic_stories set link_mined = 't'" );

    my $num_date_changes = 10;
    $db->query( "update stories set publish_date = '2017-06-01'" );
    $db->query( <<SQL, '2018-06-01', $num_date_changes );
update stories set publish_date = ? where stories_id in 
    (select stories_id from stories order by stories_id limit ?)
SQL
    $db->query( <<SQL, '2016-06-01', $num_date_changes );
update stories set publish_date = ? where stories_id in 
    (select stories_id from stories order by stories_id desc limit ?)
SQL

    my $snapshot = { 
        topics_id => $topic->{ topics_id },
        snapshot_date => MediaWords::Util::SQL::sql_now(),
        start_date => $topic->{ start_date },
        end_date => $topic->{ end_date }
    };
    $snapshot = $db->create( 'snapshots', $snapshot );

    my $timespan_dates = 
        [ [ '2017-01-01', '2017-01-31' ], [ '2017-12-20', '2018-01-20' ], [ '2016-12-20', '2017-01-20' ] ];
    for my $dates ( @{ $timespan_dates } )
    {
        my ( $start_date, $end_date ) = @{ $dates };
        my $timespan = {
            snapshots_id => $snapshot->{ snapshots_id },
            start_date => $start_date, 
            end_date => $end_date,
            period => 'monthly',
            story_count => 0,
            story_link_count => 0,
            medium_count => 0,
            medium_link_count => 0,
            tweet_count => 0
        };
        $timespan = $db->create( 'timespans', $timespan );
    }

    MediaWords::TM::Mine::set_stories_respidering( $db, $topic, $snapshot->{ snapshots_id } );

    ( $got_num_respider_stories ) = $db->query( "select count(*) from topic_stories where not link_mined" )->flat;
    is( $got_num_respider_stories, 2 * $num_date_changes, "dated stories marked for respidering" );

    my ( $got_num_archived_timespans ) = $db->query(
        "select count(*) from timespans where archive_snapshots_id = ?", $snapshot->{ snapshots_id } )->flat;
    is( $got_num_archived_timespans, 2, "number of archive timespans" );
}

sub test_mine($)
{
    my ( $db ) = @_;

    ( $db );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_die_if_max_stories_exceeded );
    MediaWords::Test::DB::test_on_test_database( \&test_respider );
}

main();
