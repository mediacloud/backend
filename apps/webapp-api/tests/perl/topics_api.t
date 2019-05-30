use strict;
use warnings;

use Catalyst::Test 'MediaWords';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use List::MoreUtils qw/uniq/;
use List::Util "shuffle";
use Math::Prime::Util;
use Readonly;
use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Auth::Roles;
use MediaWords::Solr::Query::Parse;
use MediaWords::Test::API;
use MediaWords::Test::Rows;
use MediaWords::Test::Solr;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;
use MediaWords::JobManager::Job;
use MediaWords::JobManager::AbstractStatefulJob;
use MediaWords::Test::DB::Create;

Readonly my $TEST_HTTP_SERVER_PORT => '3000';

Readonly my $TEST_HTTP_SERVER_URL => 'http://localhost:' . $TEST_HTTP_SERVER_PORT;

# This should match the DEFAULT_STORY_LIMIT in Stories.pm
Readonly my $DEFAULT_STORY_LIMIT => 20;

# A constant used to generate consistent orderings in test sorts
Readonly my $TEST_MODULO => 6;

sub add_topic_link($$$$)
{
    my ( $db, $topic, $story, $ref_story ) = @_;

    $db->create(
        'topic_links',
        {
            topics_id      => $topic->{ topics_id },
            stories_id     => $story,
            url            => 'http://foo',
            redirect_url   => 'http://foo',
            ref_stories_id => $ref_story,
        }
    );

}

sub add_topic_story($$$)
{
    my ( $db, $topic, $story ) = @_;

    $db->create( 'topic_stories', { stories_id => $story->{ stories_id }, topics_id => $topic->{ topics_id } } );
}

sub create_stories($$)
{
    my ( $db, $stories ) = @_;

    my $media = MediaWords::Test::DB::Create::create_test_story_stack( $db, $stories );
}

sub create_test_data($$)
{

    my ( $test_db, $topic_media_sources ) = @_;

    my $NUM_LINKS_PER_PAGE = 10;

    srand( 3 );

    # populate topics table
    my $topic = $test_db->create(
        'topics',
        {
            name                => 'foo',
            solr_seed_query     => '',
            solr_seed_query_run => 'f',
            pattern             => '',
            description         => 'test topic',
            start_date          => '2014-04-01',
            end_date            => '2014-06-01',
            job_queue           => 'mc',
            max_stories         => 100_000
        }
    );

    # populate topics_stories table
    # only include stories with id not multiples of $TEST_MODULO
    my $all_stories   = {};
    my $topic_stories = [];

    for my $m ( values( %{ $topic_media_sources } ) )
    {
        for my $f ( values( %{ $m->{ feeds } } ) )
        {
            while ( my ( $num, $story ) = each( %{ $f->{ stories } } ) )
            {
                if ( $num % $TEST_MODULO )
                {
                    my $cs = add_topic_story( $test_db, $topic, $story );
                    push @{ $topic_stories }, $story->{ stories_id };
                }
                $all_stories->{ int( $num ) } = $story->{ stories_id };
            }
        }
    }

    # populate topics_links table
    while ( my ( $num, $story_id ) = each %{ $all_stories } )
    {
        my @factors = Math::Prime::Util::factor( $num );
        foreach my $factor ( uniq @factors )
        {
            if ( $factor != $num )
            {
                add_topic_link( $test_db, $topic, $all_stories->{ $factor }, $story_id );
            }
        }
    }

    $topic_media_sources = MediaWords::Test::DB::Create::add_content_to_test_story_stack( $test_db, $topic_media_sources );

    MediaWords::JobManager::Job::run_remotely( 'MediaWords::Job::TM::SnapshotTopic', { topics_id => $topic->{ topics_id } } );

    MediaWords::Test::Solr::setup_test_index( $test_db );

    # FIXME commented out because we're probably doing the same thing twice
    # MediaWords::JobManager::Job::run_remotely(  #
    #     'MediaWords::Job::ImportSolrDataForTesting',  #
    #     { throttle => 0 },   #
    # );
}

sub test_media_list($)
{
    my ( $data ) = @_;

    my $actual_response = MediaWords::Test::API::test_get( '/api/v2/topics/1/media/list' );

    ok( scalar @{ $actual_response->{ media } } == 3,
        "returned unexpected number of media scalar $actual_response->{ media }" );

    # Check descending link count
    foreach my $m ( 1 .. $#{ $actual_response->{ media } } )
    {
        ok( $actual_response->{ media }[ $m ]->{ inlink_count } <= $actual_response->{ media }[ $m - 1 ]->{ inlink_count } );
    }

    # Check that we have right number of inlink counts for each media source

    my $topic_stories = _get_story_link_counts( $data );

    my $inlink_counts = { F => 4, D => 2, A => 0 };

    foreach my $mediasource ( @{ $actual_response->{ media } } )
    {
        ok( $mediasource->{ inlink_count } == $inlink_counts->{ $mediasource->{ name } } );
    }
}

sub test_media_links($)
{
    my ( $db ) = @_;

    # FIXME I don't know why, but if we pick timespans_id using the following
    # (commented out) query, sometimes it gets a timespan without any stories
    # whatsoever
    #my ( $timespans_id ) = $db->query( <<SQL )->flat();
    #select timespans_id from timespans t where period = 'overall' and foci_id is null;
    #SQL

    # What seems to work though is just hardcoding timespans_id
    my $timespans_id = 1;

    my $limit = 1000;

    my $expected_links = $db->query( <<SQL, $timespans_id, $limit )->hashes();
select source_media_id, ref_media_id
    from snap.medium_links sl
    where
        timespans_id = ?
    order by source_media_id, ref_media_id
    limit ?
SQL

    ok( scalar( @{ $expected_links } ) > 1, "test_media_links: more than one link" );

    my $r = MediaWords::Test::API::test_get( '/api/v2/topics/1/media/links', { limit => $limit, timespans_id => $timespans_id } );

    my $got_links = $r->{ links };

    is_deeply( $got_links, $expected_links, "test_media_links: links returned" );
}

sub test_stories_links($)
{
    my ( $db ) = @_;

    # FIXME I don't know why, but if we pick timespans_id using the following
    # (commented out) query, sometimes it gets a timespan without any stories
    # whatsoever
    #my ( $timespans_id ) = $db->query( <<SQL )->flat();
    #select timespans_id from timespans t where period = 'overall' and foci_id is null;
    #SQL

    # What seems to work though is just hardcoding timespans_id
    my $timespans_id = 1;

    my $limit = 1000;

    my $expected_links = $db->query( <<SQL, $timespans_id, $limit )->hashes();
select source_stories_id, ref_stories_id
    from snap.story_links sl
    where
        timespans_id = ?
    order by source_stories_id, ref_stories_id
    limit ?
SQL

    ok( scalar( @{ $expected_links } ) > 1, "test_stories_links: more than one link" );

    my $r = MediaWords::Test::API::test_get( '/api/v2/topics/1/stories/links', { limit => $limit, timespans_id => $timespans_id } );

    my $got_links = $r->{ links };

    is_deeply( $got_links, $expected_links, "test_stories_links: links returned" );
}

sub test_story_list_count()
{

    # The number of stories returned in stories/list matches the count in timespan

    my $story_limit = 10;

    my $actual_response = MediaWords::Test::API::test_get( '/api/v2/topics/1/stories/list', { limit => $story_limit } );

    is( scalar @{ $actual_response->{ stories } }, $story_limit, "story limit" );
}

sub test_story_list_paging($)
{
    my ( $db ) = @_;

    my ( $topics_id ) = $db->query( "select topics_id from topics" )->flat();

    my ( $timespans_id ) = $db->query( <<SQL )->flat();
select timespans_id from timespans t where period = 'overall' and foci_id is null;
SQL

    my ( $expected_stories_count ) = $db->query( <<SQL, $timespans_id )->flat();
select count(*) from snap.story_link_counts where timespans_id = ?
SQL

    my $limit = 3;

    my $r = MediaWords::Test::API::test_get( "/api/v2/topics/$topics_id/stories/list", { timespans_id => $timespans_id, limit => $limit } );

    my $got_stories_count = scalar( @{ $r->{ stories } } );

    while ( my $next_link_id = $r->{ link_ids }->{ next } )
    {
        $r = MediaWords::Test::API::test_get( "/api/v2/topics/$topics_id/stories/list", { link_id => $next_link_id } );
        $got_stories_count += scalar( @{ $r->{ stories } } );
    }

    is( $got_stories_count, $expected_stories_count, "stories/list paging count" );
}

sub _get_story_link_counts($)
{
    my $data = shift;

    # umber of prime factors outside the media source
    my $counts = {
        1  => 0,
        2  => 0,
        3  => 0,
        4  => 0,
        5  => 0,
        7  => 0,
        8  => 1,
        9  => 1,
        10 => 2,
        11 => 0,
        13 => 0,
        14 => 2,
        15 => 0
    };

    my %return_counts = map { "story " . $_ => $counts->{ $_ } } keys %{ $counts };
    return \%return_counts;

}

sub test_default_sort($)
{

    my $data = shift;

    my $base_url = '/api/v2/topics/1/stories/list';

    my $sort_key = "inlink_count";

    my $expected_counts = _get_story_link_counts( $data );

    _test_sort( $data, $expected_counts, $base_url, $sort_key );

}

sub _test_sort($$$$)
{

    # Make sure that only expected stories are in stories list response
    # in the appropriate order

    my ( $data, $expected_counts, $base_url, $sort_key ) = @_;

    my $actual_response = MediaWords::Test::API::test_get( $base_url, { limit => 20, sort => $sort_key } );

    my $actual_stories_inlink_counts = {};
    my $actual_stories_order         = ();

    foreach my $story ( @{ $actual_response->{ stories } } )
    {
        $actual_stories_inlink_counts->{ $story->{ 'title' } } = $story->{ $sort_key };
        my @story_info = ( $story->{ $sort_key }, $story->{ 'stories_id' } );
        push @{ $actual_stories_order }, \@story_info;
    }

    is_deeply( $actual_stories_inlink_counts, $expected_counts, 'expected stories' );
}

# test topics create and update
sub test_topics_crud($)
{
    my ( $db ) = @_;

    # verify required params
    MediaWords::Test::API::test_post( '/api/v2/topics/create', {}, 1 );

    my $label = "create topic";

    MediaWords::Test::DB::Create::create_test_story_stack_numerated( $db, 10, 2, 2, $label );
    $db->query( "insert into tag_sets ( name ) values ( 'create topic' )" );
    $db->query( "insert into tags ( tag, tag_sets_id ) select m.name, ts.tag_sets_id from media m, tag_sets ts" );

    my $media_ids = $db->query( "select media_id from media limit 5" )->flat;
    my $tags_ids  = $db->query( "select tags_id from tags limit 5" )->flat;

    my $input = {
        name                 => "$label name ",
        description          => "$label description",
        solr_seed_query      => "$label query",
        max_iterations       => 12,
        start_date           => '2016-01-01',
        end_date             => '2017-01-01',
        is_public            => 1,
        is_logogram          => 0,
        is_story_index_ready => 1,
        ch_monitor_id        => 123456,
        media_ids            => $media_ids,
        media_tags_ids       => $tags_ids,
        max_stories          => 1234,
    };

    my $r = MediaWords::Test::API::test_post( '/api/v2/topics/create', $input );

    ok( $r->{ topics }, "$label JSON includes topics" );
    my $got_topic = $r->{ topics }->[ 0 ];

    my $exists_in_db = $db->find_by_id( "topics", $got_topic->{ topics_id } );
    ok( $exists_in_db, "$label topic exists in db" );

    my $test_fields =
      [ qw/name description solr_seed_query max_ierations start_date end_date is_public ch_monitor_id max_stories/ ];
    map { is( $got_topic->{ $_ }, $input->{ $_ }, "$label $_" ) } @{ $test_fields };

    my $expected_pattern = MediaWords::Solr::Query::Parse::parse_solr_query( $input->{ solr_seed_query } )->re();
    is( $got_topic->{ pattern }, $expected_pattern, "$label pattern" );

    my $topics_id = $got_topic->{ topics_id };

    my $got_media_ids = [ map { $_->{ media_id } } @{ $got_topic->{ media } } ];
    is_deeply( [ sort @{ $media_ids } ], [ sort @{ $media_ids } ], "$label media ids" );

    my $got_tags_ids = [ map { $_->{ tags_id } } @{ $got_topic->{ media_tags } } ];
    is_deeply( [ sort @{ $got_tags_ids } ], [ sort @{ $tags_ids } ], "$label media tag ids" );

    is( $got_topic->{ job_queue }, 'mc', "$label queue for admin user" );

    my $update_media_ids = [ @{ $media_ids } ];
    pop( @{ $update_media_ids } );
    my $update_tags_ids = [ @{ $tags_ids } ];
    pop( @{ $update_tags_ids } );

    my $update = {
        name                 => "$label name update",
        description          => "$label description update",
        solr_seed_query      => "$label query update",
        max_iterations       => 22,
        start_date           => '2016-01-02',
        end_date             => '2017-01-02',
        is_public            => 0,
        is_logogram          => 0,
        is_story_index_ready => 0,
        ch_monitor_id        => 1234567,
        media_ids            => $update_media_ids,
        media_tags_ids       => $update_tags_ids,
        max_stories          => 2345
    };

    $label = 'update topic';

    $r = MediaWords::Test::API::test_put( "/api/v2/topics/$topics_id/update", $update );

    ok( $r->{ topics }, "$label JSON includes topics" );
    $got_topic = $r->{ topics }->[ 0 ];

    map { is( $got_topic->{ $_ }, $update->{ $_ }, "$label $_" ) } @{ $test_fields };

    $got_media_ids = [ map { $_->{ media_id } } @{ $got_topic->{ media } } ];
    is_deeply( [ sort @{ $got_media_ids } ], [ sort @{ $update_media_ids } ], "$label media ids" );

    $got_tags_ids = [ map { $_->{ tags_id } } @{ $got_topic->{ media_tags } } ];
    is_deeply( [ sort @{ $got_tags_ids } ], [ sort @{ $update_tags_ids } ], "$label media tag ids" );

    # verify fix for bug dealing with undef max_stories using most of the create topic data from $input above
    $input->{ max_stories } = undef;
    $input->{ name }        = 'null max stories';
    $r = MediaWords::Test::API::test_post( '/api/v2/topics/create', $input );

    is( $r->{ topics }->[ 0 ]->{ max_stories }, 100_000 );
}

# test topics/spider call
sub test_topics_spider($)
{
    my ( $db ) = @_;

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, 'spider test' );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { solr_seed_query => 'BOGUSQUERYTORETURNOSTORIES' } );
    my $topics_id = $topic->{ topics_id };

    my $snapshot = {
        topics_id     => $topics_id,
        snapshot_date => MediaWords::Util::SQL::sql_now(),
        start_date    => $topic->{ start_date },
        end_date      => $topic->{ end_date },
    };
    $snapshot = $db->create( 'snapshots', $snapshot );
    my $snapshots_id = $snapshot->{ snapshots_id };

    my $r = MediaWords::Test::API::test_post( "/api/v2/topics/$topics_id/spider", { snapshots_id => $snapshots_id } );

    ok( $r->{ job_state }, "spider return includes job_state" );

    is( $r->{ job_state }->{ state },        $MediaWords::JobManager::AbstractStatefulJob::STATE_QUEUED, "spider state" );
    is( $r->{ job_state }->{ topics_id },    $topic->{ topics_id },                  "spider topics_id" );
    is( $r->{ job_state }->{ snapshots_id }, $snapshots_id,                          "spider snapshots_id" );

    $r = MediaWords::Test::API::test_get( "/api/v2/topics/$topics_id/spider_status" );

    ok( $r->{ job_states }, "spider status return includes job_states" );

    is( $r->{ job_states }->[ 0 ]->{ state },        $MediaWords::JobManager::AbstractStatefulJob::STATE_QUEUED, "spider_status state" );
    is( $r->{ job_states }->[ 0 ]->{ topics_id },    $topic->{ topics_id },                  "spider_status topics_id" );
    is( $r->{ job_states }->[ 0 ]->{ snapshots_id }, $snapshots_id,                          "spider_status snapshots_id" );
}

# test topics/list
sub test_topics_list($)
{
    my ( $db ) = @_;

    my $label = "topics list";

    my $match_fields = [
        qw/name pattern solr_seed_query solr_seed_query_run description max_iterations start_date end_date state
          message job_queue max_stories is_logogram is_story_index_ready/
    ];

    my $topic_private_a = MediaWords::Test::DB::Create::create_test_topic( $db, "label private a" );
    my $topic_private_b = MediaWords::Test::DB::Create::create_test_topic( $db, "label private b" );
    my $topic_public_a  = MediaWords::Test::DB::Create::create_test_topic( $db, "label public a" );
    my $topic_public_b  = MediaWords::Test::DB::Create::create_test_topic( $db, "label public b" );

    map { $db->update_by_id( 'topics', $_->{ topics_id }, { is_public => 't' } ) } ( $topic_public_a, $topic_public_b );

    {
        my $r = MediaWords::Test::API::test_get( "/api/v2/topics/list", {} );
        my $expected_topics = $db->query( "select * from topics order by topics_id" )->hashes;
        ok( $r->{ topics }, "$label topics field present" );
        MediaWords::Test::Rows::rows_match( $label, $r->{ topics }, $expected_topics, 'topics_id', $match_fields );
    }

    {
        $label = "$label with name";
        my $r = MediaWords::Test::API::test_get( "/api/v2/topics/list", { name => 'label private a' } );
        my $expected_topics = $db->query( "select * from topics where name = 'label private a'" )->hashes;
        ok( $r->{ topics }, "$label topics field present" );
        MediaWords::Test::Rows::rows_match( $label, $r->{ topics }, $expected_topics, 'topics_id', $match_fields );
    }

    {
        $label = "$label public";
        my $r = MediaWords::Test::API::test_get( "/api/v2/topics/list", { public => 1 } );
        my $expected_topics = $db->query( "select * from topics where name % 'public ?'" )->hashes;
        ok( $r->{ topics }, "$label topics field present" );
        MediaWords::Test::Rows::rows_match( $label, $r->{ topics }, $expected_topics, 'topics_id', $match_fields );
    }

    {
        $label = "$label list only permitted topics";
        my $api_key = MediaWords::Test::API::get_test_api_key();

        my $auth_user = $db->query(
            <<SQL,
            SELECT auth_users_id
            FROM auth_user_api_keys
            WHERE api_key = ?
SQL
            $api_key
        )->hash;
        my $auth_users_id = $auth_user->{ auth_users_id };

        $db->query( "delete from auth_users_roles_map where auth_users_id = ?", $auth_users_id );

        my $r               = MediaWords::Test::API::test_get( "/api/v2/topics/list" );
        my $expected_topics = $db->query( "select * from topics where name % 'public ?'" )->hashes;
        ok( $r->{ topics }, "$label topics field present" );

        MediaWords::Test::Rows::rows_match( $label, $r->{ topics }, $expected_topics, 'topics_id', $match_fields );

        $db->query( <<SQL, $auth_users_id, $MediaWords::DBI::Auth::Roles::List::ADMIN );
insert into auth_users_roles_map ( auth_users_id, auth_roles_id )
    select ?, auth_roles_id from auth_roles where role = ?
SQL
    }

}

# test topics/* calls
sub test_topics($)
{
    my ( $db ) = @_;

    test_topics_list( $db );
    test_topics_crud( $db );
    test_topics_spider( $db );
}

# test snapshots/create
sub test_snapshots_create($)
{
    my ( $db ) = @_;

    my $label = 'snapshot create';

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, $label );

    my $r = MediaWords::Test::API::test_post( "/api/v2/topics/$topic->{ topics_id }/snapshots/create", {} );

    ok( $r->{ snapshot },                   "$label snapshot returned" );
    ok( $r->{ snapshot }->{ snapshots_id }, "$label snapshots_id" );

    my $snapshot = $db->find_by_id( "snapshots", $r->{ snapshot }->{ snapshots_id } );

    ok( $snapshot, "snapshot created" );
}

# test snapshots/generate and /generate_status
sub test_snapshots_generate($)
{
    my ( $db ) = @_;

    my $label = 'snapshot generate';

    my $topic = MediaWords::Test::DB::Create::create_test_topic( $db, $label );

    $topic = $db->update_by_id( 'topics', $topic->{ topics_id }, { solr_seed_query => 'BOGUSQUERYTORETURNOSTORIES' } );
    my $topics_id = $topic->{ topics_id };

    my $r = MediaWords::Test::API::test_post( "/api/v2/topics/$topics_id/snapshots/generate", {} );

    ok( $r->{ job_state }, "$label return includes job_state" );

    ok(
        $r->{ 'job_state' }->{ 'state' } eq $MediaWords::JobManager::AbstractStatefulJob::STATE_QUEUED or    #
        $r->{ 'job_state' }->{ 'state' } eq $MediaWords::JobManager::AbstractStatefulJob::STATE_RUNNING,     #
        "$label state"
    );
    is( $r->{ job_state }->{ topics_id }, $topic->{ topics_id }, "$label topics_id" );

    $r = MediaWords::Test::API::test_get( "/api/v2/topics/$topics_id/snapshots/generate_status" );

    $label = 'snapshot generate_status';

    ok( $r->{ job_states }, "$label return includes job_states" );

    # Given that the snapshot worker is running, the job could be at any state
    # by now, so we only test that it's set
    ok( $r->{ job_states }->[ 0 ]->{ state }, "$label status state" );
    is( $r->{ job_states }->[ 0 ]->{ topics_id }, $topic->{ topics_id }, "$label topics_id" );
}

# test snapshots/* calls
sub test_snapshots($)
{
    my ( $db ) = @_;

    test_snapshots_create( $db );
    test_snapshots_generate( $db );
}

# test stories/facebook list
sub test_stories_facebook($)
{
    my ( $db ) = @_;

    my $label = "stories/facebook";

    my $topic   = $db->query( "select * from topics limit 1" )->hash;
    my $stories = $db->query( "select * from snap.live_stories limit 10" )->hashes;

    my $expected_ss = [];
    for my $story ( @{ $stories } )
    {
        my $stories_id = $story->{ stories_id };
        my $ss         = $db->create(
            'story_statistics',
            {
                stories_id                => $stories_id,
                facebook_share_count      => $stories_id + 1,
                facebook_comment_count    => $stories_id + 2,
                facebook_api_collect_date => $story->{ publish_date }
            }
        );

        push( @{ $expected_ss }, $ss );
    }

    my $r = MediaWords::Test::API::test_get( "/api/v2/topics/$topic->{ topics_id }/stories/facebook", {} );

    my $got_ss = $r->{ counts };
    ok( $got_ss, "$label counts field present" );

    my $fields = [ qw/facebook_share_count facebook_comment_count facebook_api_collect_date/ ];
    MediaWords::Test::Rows::rows_match( $label, $got_ss, $expected_ss, 'stories_id', $fields );
}

sub test_stories_count($)
{
    my ( $db ) = @_;

    my ( $expected_count ) = $db->query( <<SQL )->flat;
select count(*)
    from snap.story_link_counts slc
        join timespans t using ( timespans_id )
    where
        t.period = 'overall' and
        t.foci_id is null
SQL

    my $topic = $db->query( "select * from topics limit 1" )->hash;

    {
        my $r = MediaWords::Test::API::test_get( "/api/v2/topics/$topic->{ topics_id }/stories/count", {} );
        is( $r->{ count }, $expected_count, "topics/stories/count" );
    }

    {
        my $r = MediaWords::Test::API::test_get( "/api/v2/topics/$topic->{ topics_id }/stories/count" );

        is( $r->{ count }, $expected_count, "topics/stories/count split count" );
    }
}

sub test_media_search($)
{
    my ( $db ) = @_;

    my $topic = $db->query( "select * from topics order by topics_id limit 1" )->hash();

    my ( $sentence ) = $db->query( <<SQL, $topic->{ topics_id } )->flat();
select ss.sentence
    from story_sentences ss
        join topic_stories ts using ( stories_id )
    where
        topics_id = ?
    order by story_sentences_id
    limit 1
SQL

    # we just need a present word to search for, so use the first word in the first sentence
    my $sentence_words = [ split( ' ', $sentence ) ];
    my $search_word = $sentence_words->[ 0 ];

    # use a regex to manually find all media sources matching the search word
    my $expected_media_ids = $db->query( <<SQL, $topic->{ topics_id }, $search_word )->flat();
select distinct m.media_id 
    from media m 
        join stories s using ( media_id ) 
        join topic_stories ts using ( stories_id )
        join story_sentences ss using ( stories_id )
    where
        ss.sentence ~* ('[[:<:]]'|| \$2 ||'[[:>:]]') and
        ts.topics_id = \$1
    order by media_id
SQL

    ok( scalar( @{ $expected_media_ids } ) > 0, "media list q search found media ids: topic $topic->{ topics_id }, search word $search_word" );

    my $r = MediaWords::Test::API::test_get( "/api/v2/topics/$topic->{ topics_id }/media/list", { q => $search_word } );

    my $got_media = $r->{ media };
    my $got_media_ids = [ sort { $a <=> $b } map { $_->{ media_id } } @{ $got_media } ];

    is_deeply( $expected_media_ids, $got_media_ids, "media/list q search: topic $topic->{ topics_id }, search word $search_word" );
}

sub test_topics_api($)
{
    my $db = shift;

    my $stories = {
        A => {
            B => [ 1, 2, 3 ],
            C => [ 4, 5, 6, 15 ]
        },
        D => { E => [ 7, 8, 9 ] },
        F => {
            G => [ 10, ],
            H => [ 11, 12, 13, 14, ]
        }
    };

    MediaWords::Test::API::setup_test_api_key( $db );

    my $topic_media = create_stories( $db, $stories );

    create_test_data( $db, $topic_media );
    test_story_list_count();
    test_story_list_paging( $db );
    test_default_sort( $stories );
    test_media_list( $stories );
    test_media_search( $db );
    test_stories_facebook( $db );

    test_topics( $db );
    test_snapshots( $db );

    test_stories_count( $db );
    test_stories_links( $db );
    test_media_links( $db );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_topics_api( $db );

    done_testing();
}

main();
