use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::TM::Snapshot;
use MediaWords::TM::Stories;
use MediaWords::Test::Solr;
use MediaWords::Test::DB::Create;
use MediaWords::Util::ParseJSON;

my $NUM_STORIES = 100;
my $NUM_TSQ_STORIES = 10;
my $NUM_FOCUS_STORIES = 50;

my $NUM_AUTHORS = 7;
my $NUM_CHANNELS = 3;

my $FOCUS_CONTENT = 'focuscontentmatch';

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

        if ( $i <= $NUM_FOCUS_STORIES )
        {
            $story->{ content } = $FOCUS_CONTENT;
        }

        MediaWords::Test::DB::Create::add_content_to_test_story( $db, $story, $feed );
    }

    MediaWords::Test::Solr::setup_test_index( $db );
}

sub add_topic_post_story
{
    my ( $db, $topic, $tpd, $story, $post_id, $author ) = @_;

    $author //= "author " . $post_id % $NUM_AUTHORS;

    my $channel = "channel " . $post_id % $NUM_CHANNELS;

    my $tp = {
        topics_id => $tpd->{ topics_id },
        topic_post_days_id => $tpd->{ topic_post_days_id },
        post_id => $post_id,
        content => 'foo',
        author => $author,
        publish_date => $topic->{ start_date },
        data => '{}',
        channel => $channel
    };
    $tp = $db->create( 'topic_posts', $tp );

    my $tpu = {
        topics_id => $tp->{ topics_id },
        topic_posts_id => $tp->{ topic_posts_id },
        url => $story->{ url },
    };
    $tpu = $db->create( 'topic_post_urls', $tpu );

    my $tsu = {
        topics_id => $topic->{ topics_id },
        topic_seed_queries_id => $tpd->{ topic_seed_queries_id },
        url => $story->{ url },
        stories_id => $story->{ stories_id },
        topic_post_urls_id => $tpu->{ topic_post_urls_id },
    };
    $tsu = $db->create( 'topic_seed_urls', $tsu );
}

sub add_test_seed_query($$)
{
    my ( $db, $topic ) = @_;

    my $tsq = {
        source => 'csv',
        platform => 'generic_post',
        topics_id => $topic->{ topics_id },
        query => 'foo'
    };
    $tsq = $db->create( 'topic_seed_queries', $tsq );

    my $stories = $db->query( <<SQL,
        SELECT *
        FROM stories
        LIMIT ?
SQL
        $NUM_TSQ_STORIES
    )->hashes;

    my $tpd = {
        topics_id => $tsq->{ topics_id },
        topic_seed_queries_id => $tsq->{ topic_seed_queries_id },
        day => $topic->{ start_date },
        num_posts_stored => 1,
        num_posts_fetched => 1,
    };
    $tpd = $db->create( 'topic_post_days', $tpd );

    while ( my ( $i, $story ) = each ( @{ $stories } ) )
    {
        add_topic_post_story( $db, $topic, $tpd, $story, $i );
    }

    # now add enough posts from a single author that they should all be ignores
    for my $i ( 1 .. 200 )
    {
        my $post_id = scalar( @{ $stories } ) + $i;
        add_topic_post_story( $db, $topic, $tpd, $stories->[ 0 ], $post_id, 'bot author' );
    }

    return $tsq;
}

# validate that a url sharing focus and timespan are created
sub validate_sharing_timespan
{
    my ( $db ) = @_;

    my $topic_seed_queries = $db->query( <<SQL
        SELECT *
        FROM topic_seed_queries
SQL
    )->hashes;

    for my $tsq ( @{ $topic_seed_queries } )
    {
        my $got_focus = $db->query( <<SQL,
            SELECT *
            FROM foci
            WHERE
                topics_id = ? AND
                (arguments->>'topic_seed_queries_id')::BIGINT = ?
SQL
            $tsq->{ topics_id }, $tsq->{ topic_seed_queries_id }
        )->hash;
        ok( $got_focus );

        my $got_timespan = $db->query( <<SQL,
            SELECT *
            FROM timespans
            WHERE
                topics_id = ? AND
                period = 'overall' AND
                foci_id = ?
SQL
            $got_focus->{ topics_id }, $got_focus->{ foci_id }
        )->hash;
        ok( $got_timespan );

        my $got_story_link_counts = $db->query( <<SQL,
            SELECT *
            FROM snap.story_link_counts
            WHERE
                topics_id = ? AND
                timespans_id = ?
SQL
            $got_timespan->{ topics_id }, $got_timespan->{ timespans_id }
        )->hashes;

        is( scalar( @{ $got_story_link_counts } ), $NUM_TSQ_STORIES );

        my $got_story_link_count_counts = $db->query( <<SQL,
            SELECT *
            FROM snap.story_link_counts
            WHERE
                topics_id = ? AND
                timespans_id = ? AND
                post_count = 1 AND
                author_count = 1 AND
                channel_count = 1
SQL
            $got_timespan->{ topics_id }, $got_timespan->{ timespans_id }
        )->hashes;

       is( scalar( @{ $got_story_link_count_counts } ), $NUM_TSQ_STORIES );
   }
}

sub add_boolean_query_focus($$)
{
    my ( $db, $topic ) = @_;

    my $fsd = {
        topics_id => $topic->{ topics_id },
        name => 'boolean query set',
        description => 'boolean query set',
        focal_technique => 'Boolean Query'
    };
    $fsd = $db->create( 'focal_set_definitions', $fsd );

    my $fd = {
        topics_id => $topic->{ topics_id },
        focal_set_definitions_id => $fsd->{ focal_set_definitions_id },
        name => 'boolean query',
        description => 'boolean query',
        arguments => MediaWords::Util::ParseJSON::encode_json( { query => $FOCUS_CONTENT } ),
    };
    $fd = $db->create( 'focus_definitions', $fd );

    return $fd;
}

sub validate_query_focus($$)
{
    my ( $db, $snapshot ) = @_;

    my $got_focus = $db->query( <<SQL,
        SELECT f.*
        FROM foci AS f
            INNER JOIN focal_sets AS fd ON
                f.topics_id = fd.topics_id AND
                f.focal_sets_id = fd.focal_sets_id
        WHERE
            fd.focal_technique = 'Boolean Query' AND
            fd.topics_id = ? AND
            fd.snapshots_id = ?
SQL
        $snapshot->{ topics_id }, $snapshot->{ snapshots_id }
    )->hash();

    ok( $got_focus, "query focus exists after snapshot" );

    my $got_timespan = $db->query( <<SQL,
        SELECT t.*
        FROM timespans AS t
        WHERE
            topics_id = ? AND
            snapshots_id = ? AND
            foci_id = ? AND
            period = 'overall'
SQL
        $snapshot->{ topics_id }, $snapshot->{ snapshots_id }, $got_focus->{ foci_id }
    )->hash();

    ok( $got_timespan );

    my $got_stories = $db->query( <<SQL,
        SELECT *
        FROM snap.story_link_counts
        WHERE
            topics_id = ? AND
            timespans_id = ?
SQL
        $got_timespan->{ topics_id }, $got_timespan->{ timespans_id }
    )->hashes();

    is( scalar( @{ $got_stories } ), $NUM_FOCUS_STORIES, "correct number of stories in focus timespan" );
}

sub test_snapshot($)
{
    my ( $db ) = @_;

    srand( 3 );

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'test snapshot' );

    my $topics_id = $topic->{ topics_id };

    add_test_topic_stories( $db, $topic, $NUM_STORIES, 'test snapshot' );

    my $expected_seed_query = add_test_seed_query( $db, $topic );

    my $tag_set = $db->query( <<SQL
        INSERT INTO tag_sets (name)
        VALUES ('foo')
        RETURNING *
SQL
    )->hash;
    my $tag = $db->query( <<SQL,
        INSERT INTO tags (tag, tag_sets_id)
        VALUES ('foo', ?)
        RETURNING *
SQL
        $tag_set->{ tag_sets_id }
    )->hash;

    my $stories = $db->query( <<SQL
        SELECT *
        FROM stories
SQL
    )->hashes;
    for my $story ( @{ $stories } )
    {
        $db->create( 'stories_tags_map', { stories_id => $story->{ stories_id }, tags_id => $tag->{ tags_id } } );

        my $ref_story = $db->query( <<SQL,
            SELECT *
            FROM stories
            WHERE stories_id = ?
SQL
            $story->{ stories_id } + 1
        )->hash;
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

    add_boolean_query_focus( $db, $topic );

    MediaWords::TM::Snapshot::snapshot_topic( $db, $topics_id );

    my $got_snapshot = $db->query( <<SQL,
        SELECT *
        FROM snapshots
        WHERE topics_id = ?
SQL
        $topic->{ topics_id }
    )->hash;

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

    my $got_stories_tags_map = $db->query( <<SQL,
        SELECT DISTINCT *
        FROM snap.stories_tags_map
        WHERE
            topics_id = ? AND
            snapshots_id = ?
SQL
        $topics_id, $snapshots_id
    )->hashes;

    is( scalar( @{ $got_stories_tags_map } ), scalar( @{ $stories } ), "snap.stories_tags_map length" );
    for my $stm ( @{ $got_stories_tags_map } )
    {
        is( $stm->{ tags_id }, $tag->{ tags_id }, "correct tag" );
    }

    my $snapshot_stories = $db->query( <<SQL,
        SELECT *
        FROM snap.stories
        WHERE
            topics_id = ? AND
            snapshots_id = ?
SQL
        $topics_id, $snapshots_id
    )->hashes;
    is( scalar( @{ $snapshot_stories } ), $NUM_STORIES , "snapshot stories" );

    my $timespan = $db->query( <<SQL,
        SELECT *
        FROM timespans
        WHERE
            topics_id = ? AND
            snapshots_id = ? AND
            period = 'overall' AND
            foci_id IS NULL
SQL
        $topics_id, $snapshots_id
    )->hash;

    ok( $timespan, "overall timespan created" );

    my $timespans_id = $timespan->{ timespans_id };

    my $slc = $db->query( <<SQL,
        SELECT *
        FROM snap.story_link_counts
        WHERE
            topics_id = ? AND
            timespans_id = ?
SQL
        $topics_id, $timespans_id
    )->hashes;

    is( scalar( @{ $slc } ), $NUM_STORIES, "story link counts" );

    validate_sharing_timespan( $db );

    validate_query_focus( $db, $got_snapshot );

    my $timespan_map;
    # allow a bit of time for the timespan maps to generate
    for my $i ( 1 .. 5 )
    {
        $timespan_map = $db->query( <<SQL,
            SELECT *
            FROM timespan_maps
            WHERE
                topics_id = ? AND
                timespans_id = ?
SQL
            $topics_id, $timespans_id
        )->hash();
        last if ( $timespan_map );
        sleep( 1 );
    }

    ok( $timespan_map, "timespan_map generated" );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_snapshot( $db );

    done_testing();
}

main();
