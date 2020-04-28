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

    my $stories = $db->query( "select * from stories limit ?", $NUM_TSQ_STORIES )->hashes;

    my $tpd = {
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

    my $topic_seed_queries = $db->query( "select * from topic_seed_queries" )->hashes;

    for my $tsq ( @{ $topic_seed_queries } )
    {
        my $got_focus = $db->query( <<SQL, $tsq->{ topic_seed_queries_id } )->hash;
select * from foci where (arguments->>'topic_seed_queries_id')::int = ?
SQL
       ok( $got_focus );

       my $got_timespan = $db->query( <<SQL, $got_focus->{ foci_id } )->hash;
select * from timespans where period = 'overall' and foci_id = ?
SQL
       ok( $got_timespan );

       my $got_story_link_counts = $db->query( <<SQL, $got_timespan->{ timespans_id } )->hashes;
select * from snap.story_link_counts where timespans_id = ?
SQL

       is( scalar( @{ $got_story_link_counts } ), $NUM_TSQ_STORIES );

       my $got_story_link_count_counts = $db->query( <<SQL, $got_timespan->{ timespans_id } )->hashes;
select * from snap.story_link_counts
    where timespans_id = ? and post_count = 1 and author_count = 1 and channel_count = 1
SQL

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

    my $got_focus = $db->query( <<SQL, $snapshot->{ snapshots_id } )->hash();
select f.*
    from foci f
        join focal_sets fd using ( focal_sets_id )
    where
        fd.focal_technique = 'Boolean Query' and
        fd.snapshots_id = ?
SQL

    ok( $got_focus, "query focus exists after snapshot" );

    my $got_timespan = $db->query( <<SQL, $snapshot->{ snapshots_id }, $got_focus->{ foci_id } )->hash();
select t.* from timespans t where snapshots_id = ? and foci_id = ? and period = 'overall'
SQL

    ok( $got_timespan );

    my $got_stories = $db->query( <<SQL, $got_timespan->{ timespans_id } )->hashes();
select slc.* from snap.story_link_counts slc where timespans_id = ?
SQL

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

    my $tag_set = $db->query( "insert into tag_sets ( name ) values ( 'foo' ) returning *" )->hash;
    my $tag = $db->query( <<SQL, $tag_set->{ tag_sets_id } )->hash;
insert into tags ( tag, tag_sets_id ) values ( 'foo', ? ) returning *
SQL

    my $stories = $db->query( "select * from stories" )->hashes;
    for my $story ( @{ $stories } )
    {
        $db->create( 'stories_tags_map', { stories_id => $story->{ stories_id }, tags_id => $tag->{ tags_id } } );

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

    add_boolean_query_focus( $db, $topic );

    MediaWords::TM::Snapshot::snapshot_topic( $db, $topics_id );

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

    my $got_stories_tags_map = $db->query( <<SQL, $snapshots_id )->hashes;
select distinct * from snap.stories_tags_map where snapshots_id = ?
SQL

    is( scalar( @{ $got_stories_tags_map } ), scalar( @{ $stories } ), "snap.stories_tags_map length" );
    for my $stm ( @{ $got_stories_tags_map } )
    {
        is( $stm->{ tags_id }, $tag->{ tags_id }, "correct tag" );
    }

    my $snapshot_stories = $db->query( "select * from snap.stories where snapshots_id = ?", $snapshots_id )->hashes;
    is( scalar( @{ $snapshot_stories } ), $NUM_STORIES , "snapshot stories" );

    my $timespan = $db->query( <<SQL, $snapshots_id )->hash;
select * from timespans where snapshots_id = ? and period = 'overall' and foci_id is null
SQL

    ok( $timespan, "overall timespan created" );

    my $timespans_id = $timespan->{ timespans_id };

    my $slc = $db->query( "select * from snap.story_link_counts where timespans_id = ?", $timespans_id )->hashes;

    is( scalar( @{ $slc } ), $NUM_STORIES, "story link counts" );

    validate_sharing_timespan( $db );

    validate_query_focus( $db, $got_snapshot );

    my $timespan_map;
    # allow a bit of time for the timespan maps to generate
    for my $i ( 1 .. 5 )
    {
        $timespan_map = $db->query( "select * from timespan_maps where timespans_id = ?", $timespans_id )->hash();
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
