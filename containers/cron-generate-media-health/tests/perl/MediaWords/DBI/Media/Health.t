#!/usr/bin/env prove

use strict;
use warnings;

# tests for MediaWords::DBI::Media::Health

use Readonly;
use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Media::Health;

Readonly my $NUM_MEDIA            => 3;
Readonly my $NUM_FEEDS_PER_MEDIUM => 1;
Readonly my $NUM_STORIES_PER_FEED => 5;

sub test_media_health
{
    my ( $db ) = @_;

    my $test_stack = MediaWords::Test::DB::Create::create_test_story_stack_numerated(
        $db,                      #
        $NUM_MEDIA,               #
        $NUM_FEEDS_PER_MEDIUM,    #
        $NUM_STORIES_PER_FEED,    #
    );

    my $test_media = [ grep { $_->{ name } && $_->{ name } =~ /^media/ } values( %{ $test_stack } ) ];

    $test_stack = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $db, $test_stack );

    # move all stories to yesterday so that they get included in today's media_health stats
    $db->query( "update stories set publish_date = now() - interval '1 day'" );

    $db->query( <<SQL );
update media_stats ms set num_sentences = q.num_sentences, num_stories = q.num_stories
    from (
        select
                count( distinct story_sentences_id ) num_sentences,
                count( distinct stories_id ) num_stories,
                media_id,
                publish_date::date stat_date
            from
                story_sentences
            group by media_id, publish_date::date
        ) q
    where
        ms.media_id = q.media_id and
        ms.stat_date = q.stat_date
SQL

    MediaWords::DBI::Media::Health::generate_media_health( $db );

    my $mhs = $db->query( "select * from media_health" )->hashes;

    is( scalar( @{ $mhs } ), $NUM_MEDIA, "number of media_health rows" );

    for my $mh ( @{ $mhs } )
    {
        my ( $medium ) = grep { $_->{ media_id } == $mh->{ media_id } } @{ $test_media };

        ok( $medium, "found medium for media_health row $mh->{ media_id }" );

        my $expected_num_stories = $NUM_STORIES_PER_FEED * $NUM_FEEDS_PER_MEDIUM;

        is( $mh->{ num_stories }, $expected_num_stories, "number of stories for medium $mh->{ media_id }" );
        ok( $mh->{ is_healthy },      "is_healthy for $mh->{ media_id }" );
        ok( $mh->{ has_active_feed }, "has_active_feed for $mh->{ media_id }" );
    }

    $db->query( "update media_health set num_stories = 0, num_stories_y = 100, num_stories_90 = 100 where media_id = 1" );
    $db->query( "update feeds set active = 'f' where media_id = 2" );

    MediaWords::DBI::Media::Health::update_media_health_status( $db );

    my $mh1 = $db->query( "select * from media_health where media_id = 1" )->hash;
    ok( !$mh1->{ is_healthy }, "zero'd medium is_healthy should be false" );

    my $mh2 = $db->query( "select * from media_health where media_id = 2" )->hash;
    ok( !$mh2->{ has_active_feed }, "medium with no feeds should have false has_active_feed" );

}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_media_health( $db );

    done_testing();
}

main();
