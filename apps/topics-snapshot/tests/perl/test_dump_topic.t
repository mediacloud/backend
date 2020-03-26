use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Topics;
use MediaWords::TM::Dump;
use MediaWords::TM::Snapshot;
use MediaWords::TM::Snapshot::Views;
use MediaWords::Test::DB::Create;
use MediaWords::Util::CSV;

Readonly my $NUM_MEDIA => 10;
Readonly my $NUM_STORIES_PER_MEDIUM => 50;


sub main
{
    my $db = MediaWords::DB::connect_to_db();

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'foo' );
    MediaWords::Test::DB::Create::create_test_topic_stories( $db, $topic, $NUM_MEDIA, $NUM_STORIES_PER_MEDIUM );

    my $num_posts = MediaWords::Test::DB::Create::create_test_topic_posts( $db, $topic );

    my $num_stories = $NUM_MEDIA * $NUM_STORIES_PER_MEDIUM;

    MediaWords::TM::Snapshot::snapshot_topic( $db, $topic->{ topics_id } );

    my $timespan = $db->query( "select * from timespans where period = 'overall' and foci_id is null" )->hash;

    MediaWords::TM::Snapshot::Views::setup_temporary_snapshot_views( $db, $timespan );

    my $stories_csv = MediaWords::TM::Dump::get_stories_csv( $db, $timespan );
    my $got_stories = MediaWords::Util::CSV::get_encoded_csv_as_hashes( $stories_csv );
    is( scalar( @{ $got_stories } ), $num_stories );

    my $media_csv = MediaWords::TM::Dump::get_media_csv( $db, $timespan );
    my $got_media = MediaWords::Util::CSV::get_encoded_csv_as_hashes( $media_csv );
    is( scalar( @{ $got_media } ), $NUM_MEDIA );

    my $story_links_csv = MediaWords::TM::Dump::get_story_links_csv( $db, $timespan );
    my $got_story_links = MediaWords::Util::CSV::get_encoded_csv_as_hashes( $story_links_csv );
    is( scalar( @{ $got_story_links } ), $num_stories );

    my $medium_links_csv = MediaWords::TM::Dump::get_medium_links_csv( $db, $timespan );
    my $got_medium_links = MediaWords::Util::CSV::get_encoded_csv_as_hashes( $medium_links_csv );
    ok( scalar( @{ $got_medium_links } ) > 0 );

    my $topic_posts_csv = MediaWords::TM::Dump::get_topic_posts_csv( $db, $timespan );
    my $got_topic_posts = MediaWords::Util::CSV::get_encoded_csv_as_hashes( $topic_posts_csv );
    is( scalar( @{ $got_topic_posts } ), $num_posts );

    $db->query( "discard temp" );

    my $post_timespan = $db->query( "select * from timespans where period = 'overall' and foci_id is not null" )->hash;

    MediaWords::TM::Snapshot::Views::setup_temporary_snapshot_views( $db, $post_timespan );

    my $topic_post_stories_csv = MediaWords::TM::Dump::get_topic_post_stories_csv( $db, $post_timespan );
    my $got_topic_post_stories = MediaWords::Util::CSV::get_encoded_csv_as_hashes( $topic_post_stories_csv );
    is( scalar( @{ $got_topic_post_stories } ), $num_posts );

    done_testing();
}

main();
