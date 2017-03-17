use strict;
use warnings;
use utf8;

use Test::More tests => 20;
use Test::NoWarnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Controller::Api::V2::Topics' );
}

use MediaWords::Controller::Api::V2::Topics;
use MediaWords::DBI::Auth::Roles;
use MediaWords::Test::DB;

sub test_validate_max_stories($)
{
    my ( $db ) = @_;

    my $label = "test_validate_max_stories";

    my $auth_user_token = MediaWords::Test::DB::create_test_user( $db, $label );
    my $auth_user = $db->query( "select * from auth_users where api_token = ?", $auth_user_token )->hash;
    my $auth_users_id = $auth_user->{ auth_users_id };

    $db->query( "delete from auth_users_roles_map" );

    eval { MediaWords::Controller::Api::V2::Topics::_validate_max_stories( $db, 1, $auth_users_id ) };
    ok( !$@, "$label max stories less than user setting: validated $@" );

    eval { MediaWords::Controller::Api::V2::Topics::_validate_max_stories( $db, 1000000, $auth_users_id ) };
    ok( $@, "$label max stories more than user setting: died" );

    $db->query( <<SQL, $auth_users_id, $MediaWords::DBI::Auth::Roles::ADMIN );
insert into auth_users_roles_map ( auth_users_id, auth_roles_id )
    select ?, auth_roles_id from auth_roles where role = ?
SQL

    eval { MediaWords::Controller::Api::V2::Topics::_validate_max_stories( $db, 1000000, $auth_users_id ) };
    ok( !$@, "$label admin user: validate $@" );

    $db->query( "delete from auth_users_roles_map" );
    $db->query( <<SQL, $auth_users_id, $MediaWords::DBI::Auth::Roles::ADMIN_READONLY );
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

    my $auth_user_token = MediaWords::Test::DB::create_test_user( $db, $label );
    my $auth_user = $db->query( "select * from auth_users where api_token = ?", $auth_user_token )->hash;
    my $auth_users_id = $auth_user->{ auth_users_id };

    $db->query( "delete from auth_users_roles_map where auth_users_id = ?", $auth_users_id );

    my $got = MediaWords::Controller::Api::V2::Topics::_is_mc_queue_user( $db, $auth_users_id );
    ok( !$got, "$label default user should be public" );

    for my $role ( @{ $MediaWords::DBI::Auth::Roles::TOPIC_MC_QUEUE_ROLES } )
    {
        $db->query( "delete from auth_users_roles_map where auth_users_id = ?", $auth_users_id );
        $db->query( <<SQL, $auth_users_id, $MediaWords::DBI::Auth::Roles::ADMIN );
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

    my $auth_user_token = MediaWords::Test::DB::create_test_user( $db, $label );
    my $auth_user = $db->query( "select * from auth_users where api_token = ?", $auth_user_token )->hash;
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

sub test_topics
{
    my ( $db ) = @_;

    test_validate_max_stories( $db );
    test_is_mc_queue_user( $db );
    test_get_user_public_queued_job( $db );
}

sub main
{

    MediaWords::Test::DB::test_on_test_database( \&test_topics );
}

main();
