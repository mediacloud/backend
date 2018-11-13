use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::DB::Create;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;

sub test_users($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    my $num_users = 8;

    for my $i ( 1 .. $num_users )
    {
        my $auth_user = {
            email             => "foo_$i\@foo.bar",
            full_name         => "foo bar $i",
            notes             => "notes $i",
            password_hash     => 'x' x 137,
            max_topic_stories => $i
        };
        $auth_user = $db->create( 'auth_users', $auth_user );
    }

    my $expected_auth_users = $db->query( "select * from auth_users" )->hashes();

    my $label = "users/list";

    my $r = test_get( '/api/v2/users/list', {} );

    my $fields = [ qw ( email full_name notes created_date max_topic_stories ) ];
    rows_match( $label, $r->{ users }, $expected_auth_users, "auth_users_id", $fields );

    $label = "users/single";

    my $expected_single = $expected_auth_users->[ 0 ];

    $r = test_get( '/api/v2/users/single/' . $expected_single->{ auth_users_id }, {} );
    rows_match( $label, $r->{ users }, [ $expected_single ], 'auth_users_id', $fields );

    $label = "search";

    my $search_user = {
        email         => "search\@foo.bar",
        full_name     => "search",
        notes         => "notes",
        password_hash => 'x' x 137,
    };
    $search_user = $db->create( 'auth_users', $search_user );

    $label = 'update';

    $r = test_get( '/api/v2/users/list', { search => 'search' } );
    rows_match( $label, $r->{ users }, [ $search_user ], 'auth_users_id', $fields );

    my $input_data = {
        auth_users_id => $search_user->{ auth_users_id },
        email         => 'update@up.date',
        full_name     => 'up date',
        notes         => 'more notes'
    };
    $r = test_put( '/api/v2/users/update', $input_data );
    rows_match( $label, $r->{ user }, [ $input_data ], 'auth_users_id', [ qw/email full_name notes/ ] );

    $label = 'roles';

    for my $i ( 1 .. 6 )
    {
        $db->create( 'auth_roles', { role => "role_$i", description => "description $i" } );
    }

    my $expected_auth_roles = $db->query( "select * from auth_roles" )->hashes();

    $r = test_get( '/api/v2/users/list_roles', {} );
    rows_match( $label, $r->{ roles }, $expected_auth_roles, 'auth_roles_id', [ qw/role description/ ] );

    $label = 'roles update';

    my $user_role = $expected_auth_roles->[ 0 ];
    my $update_input = { auth_users_id => $search_user->{ auth_users_id }, roles => [ $user_role->{ role } ] };
    $r = test_put( '/api/v2/users/update', $update_input );

    my $role_present = $db->query( <<SQL, $search_user->{ auth_users_id }, $user_role->{ auth_roles_id } )->hash();
        select * from auth_users_roles_map where auth_users_id = \$1 and auth_roles_id = \$2
SQL

    ok( $role_present, $label );

    $label = 'roles delete';

    my $update_input = { auth_users_id => $search_user->{ auth_users_id }, roles => [] };
    $r = test_put( '/api/v2/users/update', $update_input );

    $role_present = $db->query( <<SQL, $search_user->{ auth_users_id } )->hash();
        select * from auth_users_roles_map where auth_users_id = \$1
SQL

    ok( !$role_present, $label );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_users );

    done_testing();
}

main();
