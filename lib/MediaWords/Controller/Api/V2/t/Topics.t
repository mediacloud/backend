use strict;
use warnings;
use utf8;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

use Catalyst::Test 'MediaWords';
use Readonly;
use MediaWords::Controller::Api::V2::Topics;
use MediaWords::DBI::Auth::Roles;
use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Job::Word2vec::GenerateTopicModel;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

sub test_validate_max_stories($)
{
    my ( $db ) = @_;

    my $label = "test_validate_max_stories";

    my $auth_user_api_key = MediaWords::Test::DB::create_test_user( $db, $label );
    my $auth_user = $db->query(
        <<SQL,
        SELECT auth_users_id
        FROM auth_user_api_keys
        WHERE api_key = ?
SQL
        $auth_user_api_key
    )->hash;
    my $auth_users_id = $auth_user->{ auth_users_id };

    $db->query( "delete from auth_users_roles_map" );

    eval { MediaWords::Controller::Api::V2::Topics::_validate_max_stories( $db, 1, $auth_users_id ) };
    ok( !$@, "$label max stories less than user setting: validated $@" );

    eval { MediaWords::Controller::Api::V2::Topics::_validate_max_stories( $db, 1000000, $auth_users_id ) };
    ok( $@, "$label max stories more than user setting: died" );

    $db->query( <<SQL, $auth_users_id, $MediaWords::DBI::Auth::Roles::List::ADMIN );
insert into auth_users_roles_map ( auth_users_id, auth_roles_id )
    select ?, auth_roles_id from auth_roles where role = ?
SQL

    eval { MediaWords::Controller::Api::V2::Topics::_validate_max_stories( $db, 1000000, $auth_users_id ) };
    ok( !$@, "$label admin user: validate $@" );

    $db->query( "delete from auth_users_roles_map" );
    $db->query( <<SQL, $auth_users_id, $MediaWords::DBI::Auth::Roles::List::ADMIN_READONLY );
insert into auth_users_roles_map ( auth_users_id, auth_roles_id )
    select ?, auth_roles_id from auth_roles where role = ?
SQL

    eval { MediaWords::Controller::Api::V2::Topics::_validate_max_stories( $db, 1000000, $auth_users_id ) };
    ok( !$@, "$label admin read user: validate $@" );
}

sub test_is_mc_queue_user($)
{
    my ( $db ) = @_;

    my $label = "test_is_mc_queue_user";

    my $auth_user_api_key = MediaWords::Test::DB::create_test_user( $db, $label );
    my $auth_user = $db->query(
        <<SQL,
        SELECT auth_users_id
        FROM auth_user_api_keys
        WHERE api_key = ?
SQL
        $auth_user_api_key
    )->hash;
    my $auth_users_id = $auth_user->{ auth_users_id };

    $db->query( "delete from auth_users_roles_map where auth_users_id = ?", $auth_users_id );

    my $got = MediaWords::Controller::Api::V2::Topics::_is_mc_queue_user( $db, $auth_users_id );
    ok( !$got, "$label default user should be public" );

    for my $role ( @{ $MediaWords::DBI::Auth::Roles::List::TOPIC_MC_QUEUE_ROLES } )
    {
        $db->query( "delete from auth_users_roles_map where auth_users_id = ?", $auth_users_id );
        $db->query( <<SQL, $auth_users_id, $MediaWords::DBI::Auth::Roles::List::ADMIN );
insert into auth_users_roles_map ( auth_users_id, auth_roles_id )
    select ?, auth_roles_id from auth_roles where role = ?
SQL

        my $got = MediaWords::Controller::Api::V2::Topics::_is_mc_queue_user( $db, $auth_users_id );
        ok( $got, "$label user with role '$role' should be mc" );
    }
}

sub test_get_user_public_queued_job($)
{
    my ( $db ) = @_;

    my $label = "test_get_user_public_queued_job";

    my $auth_user_api_key = MediaWords::Test::DB::create_test_user( $db, $label );
    my $auth_user = $db->query(
        <<SQL,
        SELECT auth_users_id
        FROM auth_user_api_keys
        WHERE api_key = ?
SQL
        $auth_user_api_key
    )->hash;
    my $auth_users_id = $auth_user->{ auth_users_id };

    my $got_job_state = MediaWords::Controller::Api::V2::Topics::_get_user_public_queued_job( $db, $auth_users_id );
    ok( !$got_job_state, "$label empty job queue" );

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );
    my $job_state = $db->create(
        'job_states',
        {
            class      => 'MediaWords::Job::TM::MineTopic',
            state      => 'queued',
            priority   => 'low',
            hostname   => 'localhost',
            process_id => 1,
            args       => '{ "topics_id": ' . $topic->{ topics_id } . ' }'
        }
    );

    my $topic_permission = $db->create(
        'topic_permissions',
        {
            auth_users_id => $auth_users_id,
            topics_id     => $topic->{ topics_id },
            permission    => 'admin'
        }
    );

    $got_job_state = MediaWords::Controller::Api::V2::Topics::_get_user_public_queued_job( $db, $auth_users_id );
    ok( $got_job_state, "$label queued job admin permission" );

    $topic_permission =
      $db->update_by_id( 'topic_permissions', $topic_permission->{ topic_permissions_id }, { permission => 'write' } );

    $got_job_state = MediaWords::Controller::Api::V2::Topics::_get_user_public_queued_job( $db, $auth_users_id );
    ok( $got_job_state, "$label queued job write permission" );

    $topic_permission =
      $db->update_by_id( 'topic_permissions', $topic_permission->{ topic_permissions_id }, { permission => 'read' } );

    $got_job_state = MediaWords::Controller::Api::V2::Topics::_get_user_public_queued_job( $db, $auth_users_id );
    ok( !$got_job_state, "$label queued job read permission" );

    $topic_permission =
      $db->update_by_id( 'topic_permissions', $topic_permission->{ topic_permissions_id }, { permission => 'admin' } );
    $job_state = $db->update_by_id( 'job_states', $job_state->{ job_states_id }, { state => 'running' } );

    $got_job_state = MediaWords::Controller::Api::V2::Topics::_get_user_public_queued_job( $db, $auth_users_id );
    ok( $got_job_state, "$label running job admin permission" );

    $job_state = $db->update_by_id( 'job_states', $job_state->{ job_states_id }, { state => 'error' } );

    $got_job_state = MediaWords::Controller::Api::V2::Topics::_get_user_public_queued_job( $db, $auth_users_id );
    ok( !$got_job_state, "$label error job admin permission" );

    $job_state = $db->update_by_id( 'job_states', $job_state->{ job_states_id }, { state => 'completed' } );

    $got_job_state = MediaWords::Controller::Api::V2::Topics::_get_user_public_queued_job( $db, $auth_users_id );
    ok( !$got_job_state, "$label completed job admin permission" );

    $job_state = $db->update_by_id(
        'job_states',
        $job_state->{ job_states_id },
        { state => 'queued', class => 'MediaWords::Job::TM::MineTopicPublic' }
    );

    $got_job_state = MediaWords::Controller::Api::V2::Topics::_get_user_public_queued_job( $db, $auth_users_id );
    ok( $got_job_state, "$label queued public job admin permission" );
}

# test controversies/list and single
sub test_controversies($)
{
    my ( $db ) = @_;

    my $label = "controversies/list";

    map { MediaWords::Test::DB::create_test_topic( $db, "$label $_" ) } ( 1 .. 10 );

    my $expected_topics = $db->query( "select *, topics_id controversies_id from topics" )->hashes;

    my $got_controversies = test_get( '/api/v2/controversies/list', {} );

    my $fields = [ qw/controversies_id name pattern solr_seed_query description max_iterations/ ];
    rows_match( $label, $got_controversies, $expected_topics, "controversies_id", $fields );

    $label = "controversies/single";

    my $expected_single = $expected_topics->[ 0 ];

    my $got_controversy = test_get( '/api/v2/controversies/single/' . $expected_single->{ topics_id }, {} );
    rows_match( $label, $got_controversy, [ $expected_single ], 'controversies_id', $fields );
}

# test controversy_dumps/list and single
sub test_controversy_dumps($)
{
    my ( $db ) = @_;

    my $label = "controversy_dumps/list";

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );

    for my $i ( 1 .. 10 )
    {
        $db->create(
            'snapshots',
            {
                topics_id     => $topic->{ topics_id },
                snapshot_date => '2017-01-01',
                start_date    => '2016-01-01',
                end_date      => '2017-01-01',
                note          => "snapshot $i"
            }
        );
    }

    my $expected_snapshots = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select *, topics_id controversies_id, snapshots_id controversy_dumps_id
    from snapshots
    where topics_id = ?
SQL

    my $got_cds = test_get( '/api/v2/controversy_dumps/list', { controversies_id => $topic->{ topics_id } } );

    my $fields = [ qw/controversies_id controversy_dumps_id start_date end_date note/ ];
    rows_match( $label, $got_cds, $expected_snapshots, 'controversy_dumps_id', $fields );

    $label = 'controversy_dumps/single';

    my $expected_snapshot = $expected_snapshots->[ 0 ];

    my $got_cd = test_get( '/api/v2/controversy_dumps/single/' . $expected_snapshot->{ snapshots_id }, {} );
    rows_match( $label, $got_cd, [ $expected_snapshot ], 'controversy_dumps_id', $fields );
}

# test controversy_dump_time_slices/list and single
sub test_controversy_dump_time_slices($)
{
    my ( $db ) = @_;

    my $label = "controversy_dump_time_slices/list";

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );
    my $snapshot = $db->create(
        'snapshots',
        {
            topics_id     => $topic->{ topics_id },
            snapshot_date => '2017-01-01',
            start_date    => '2016-01-01',
            end_date      => '2017-01-01',
        }
    );

    my $metrics = [
        qw/story_count story_link_count medium_count medium_link_count tweet_count /,
        qw/model_num_media model_r2_mean model_r2_stddev/
    ];
    for my $i ( 1 .. 9 )
    {
        my $timespan = {
            snapshots_id => $snapshot->{ snapshots_id },
            start_date   => '2016-01-0' . $i,
            end_date     => '2017-01-0' . $i,
            period       => 'custom'
        };

        map { $timespan->{ $_ } = $i * length( $_ ) } @{ $metrics };
        $db->create( 'timespans', $timespan );
    }

    my $expected_timespans = $db->query( <<SQL, $snapshot->{ snapshots_id } )->hashes;
select *, snapshots_id controversy_dumps_id, timespans_id controversy_dump_time_slices_id
    from timespans
    where snapshots_id = ?
SQL

    my $got_cdtss =
      test_get( '/api/v2/controversy_dump_time_slices/list', { controversy_dumps_id => $snapshot->{ snapshots_id } } );

    my $fields = [ qw/controversy_dumps_id start_date end_date period/, @{ $metrics } ];
    rows_match( $label, $got_cdtss, $expected_timespans, 'controversy_dump_time_slices_id', $fields );

    $label = 'controversy_dump_time_slices/single';

    my $expected_timespan = $expected_timespans->[ 0 ];

    my $got_cdts = test_get( '/api/v2/controversy_dump_time_slices/single/' . $expected_timespan->{ timespans_id }, {} );
    rows_match( $label, $got_cdts, [ $expected_timespan ], 'controversy_dump_time_slices_id', $fields );
}

sub test_generate_fetch_word2vec_model($)
{
    my $db = shift;

    my $topic = MediaWords::Test::DB::create_test_topic( $db, 'test_word2vec_model' );
    my $topics_id = $topic->{ topics_id };

    # Allow test user to "write" to this topic
    my $auth_user = $db->query(
        <<SQL,
        SELECT auth_users_id
        FROM auth_user_api_keys
        WHERE api_key = ?
SQL
        MediaWords::Test::API::get_test_api_key()
    )->hash;
    my $auth_users_id    = $auth_user->{ auth_users_id };
    my $topic_permission = $db->create(
        'topic_permissions',
        {
            auth_users_id => $auth_users_id,
            topics_id     => $topics_id,
            permission    => 'write'
        }
    );

    # Add all test stories to the test topic
    $db->query(
        <<SQL,
        INSERT INTO topic_stories (topics_id, stories_id)
        SELECT ?, stories_id FROM stories
SQL
        $topics_id
    );

    # Test that no models exist for topic
    {
        my $fetched_topic = test_get( "/api/v2/topics/single/$topics_id" );
        ok( $fetched_topic->{ topics }->[ 0 ]->{ word2vec_models } );
        is( ref $fetched_topic->{ topics }->[ 0 ]->{ word2vec_models }, ref( [] ) );
        is( scalar( @{ $fetched_topic->{ topics }->[ 0 ]->{ word2vec_models } } ), 0 );
    }

    # Add model generation job
    MediaWords::Job::Word2vec::GenerateTopicModel->add_to_queue( { topics_id => $topics_id } );

    # Wait for model to appear
    my $found_models_id = undef;
    for ( my $retry = 1 ; $retry <= 10 ; ++$retry )
    {
        INFO "Trying to fetch generated topic model for $retry time...";

        my $fetched_topic = test_get( "/api/v2/topics/single/$topics_id" );
        if ( scalar( @{ $fetched_topic->{ topics }->[ 0 ]->{ word2vec_models } } ) > 0 )
        {
            $found_models_id = $fetched_topic->{ topics }->[ 0 ]->{ word2vec_models }->[ 0 ]->{ models_id };
            last;
        }

        INFO "Model not found, will retry shortly";
        sleep( 1 );
    }

    ok( defined $found_models_id, "Model's ID was not found after all of the retries" );

    # Try fetching the model
    my $path = "/api/v2/topics/$topics_id/word2vec_model/$found_models_id?key=" . MediaWords::Test::API::get_test_api_key();
    my $response = request( $path );    # Catalyst::Test::request()
    ok( $response->is_success );

    my $model_data = $response->decoded_content;
    ok( defined $model_data );

    my $model_data_length = length( $model_data );
    INFO "Model data length: $model_data_length";
    ok( $model_data_length > 0 );
}

sub test_topics
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    MediaWords::Test::DB::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_validate_max_stories( $db );
    test_is_mc_queue_user( $db );
    test_get_user_public_queued_job( $db );

    test_controversies( $db );
    test_controversy_dumps( $db );
    test_controversy_dump_time_slices( $db );

    test_generate_fetch_word2vec_model( $db );
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor(    #
        \&test_topics,                                     #
        [                                                  #
            'solr_standalone',                             #
            'job_broker:rabbitmq',                         #
            'rescrape_media',                              #
            'word2vec_generate_topic_model',               #
        ]                                                  #
    );

    done_testing();
}

main();
