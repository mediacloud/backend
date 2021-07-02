use strict;
use warnings;

# tests for MediaWords::DBI::Media::Health

use Readonly;
use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Media::Health;
use MediaWords::Test::DB::Create;

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
    $db->query( <<SQL
        WITH stories_to_update AS (
            SELECT stories_id
            FROM stories
        )
        UPDATE stories SET
            publish_date = NOW() - INTERVAL '1 day'
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories_to_update
        )
SQL
    );
    $db->query( <<SQL
        WITH stories_to_update AS (
            SELECT stories_id
            FROM stories
        )
        UPDATE story_sentences SET
            publish_date = NOW() - INTERVAL '1 day'
        WHERE stories_id IN (
            SELECT stories_id
            FROM stories_to_update
        )
SQL
    );

    MediaWords::DBI::Media::Health::generate_media_health( $db );

    my $mhs = $db->query( "SELECT * FROM media_health" )->hashes;

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

    $db->query( <<SQL,
        UPDATE media_health SET
            num_stories = 0,
            num_stories_y = 100,
            num_stories_90 = 100
        WHERE media_id = 1
SQL
    );
    $db->query( "UPDATE feeds SET active = 'f' WHERE media_id = 2" );

    MediaWords::DBI::Media::Health::update_media_health_status( $db );

    my $mh1 = $db->query( "SELECT * FROM media_health WHERE media_id = 1" )->hash;
    ok( !$mh1->{ is_healthy }, "zero'd medium is_healthy should be false" );

    my $mh2 = $db->query( "SELECT * FROM media_health WHERE media_id = 2" )->hash;
    ok( !$mh2->{ has_active_feed }, "medium with no feeds should have false has_active_feed" );

}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_media_health( $db );

    done_testing();
}

main();
