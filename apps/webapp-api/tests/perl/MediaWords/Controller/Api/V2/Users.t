use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::DB;
use MediaWords::Test::API;
use MediaWords::Test::Rows;
use MediaWords::Test::Solr;

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
            has_consented     => 'false',
            active            => 'false'
        };
        $auth_user = $db->create( 'auth_users', $auth_user );

        $db->query(<<SQL,
            UPDATE auth_user_limits
            SET max_topic_stories = ?
            WHERE auth_users_id = ?
SQL
            $i, $auth_user->{ 'auth_users_id' }
        );
    }

    my $expected_auth_users =
      $db->query( "select * from auth_users join auth_user_limits using ( auth_users_id )" )->hashes();

    my $label = "users/list";

    my $r = MediaWords::Test::API::test_get( '/api/v2/users/list', {} );

    my $fields = [ qw ( email full_name notes created_date max_topic_stories weekly_requests_limit has_consented ) ];
    MediaWords::Test::Rows::rows_match( $label, $r->{ users }, $expected_auth_users, "auth_users_id", $fields );

    $label = "users/single";

    my $expected_single = $expected_auth_users->[ 0 ];

    $r = MediaWords::Test::API::test_get( '/api/v2/users/single/' . $expected_single->{ auth_users_id }, {} );
    MediaWords::Test::Rows::rows_match( $label, $r->{ users }, [ $expected_single ], 'auth_users_id', $fields );

    $label = "search";

    my $search_user = {
        email         => "search\@foo.bar",
        full_name     => "search",
        notes         => "notes",
        password_hash => 'x' x 137,
    };
    $search_user = $db->create( 'auth_users', $search_user );

    $r = MediaWords::Test::API::test_get( '/api/v2/users/list', { search => 'search' } );
    MediaWords::Test::Rows::rows_match( $label, $r->{ users }, [ $search_user ], 'auth_users_id', [ 'auth_users_id' ] );

    $label = 'update';

    my $input_data = {
        auth_users_id         => $search_user->{ auth_users_id },
        email                 => 'update@up.date',
        full_name             => 'up date',
        notes                 => 'more notes',
        active                => 1,
        has_consented         => 1,
        weekly_requests_limit => 123456,
        max_topic_stories     => 456789,
    };
    $r = MediaWords::Test::API::test_put( '/api/v2/users/update', $input_data );

    my $updated_user = $db->query( <<SQL, $search_user->{ auth_users_id } )->hash();
select au.*, aul.max_topic_stories, aul.weekly_requests_limit
    from auth_users au
        join auth_user_limits aul using ( auth_users_id )
    where au.auth_users_id = ?
SQL

    MediaWords::Test::Rows::rows_match( $label, [ $updated_user ], [ $input_data ], 'auth_users_id', [ keys( %{ $input_data } ) ] );

    $label = 'roles';

    for my $i ( 1 .. 6 )
    {
        $db->create( 'auth_roles', { role => "role_$i", description => "description $i" } );
    }

    my $expected_auth_roles = $db->query( "select * from auth_roles" )->hashes();

    $r = MediaWords::Test::API::test_get( '/api/v2/users/list_roles', {} );
    MediaWords::Test::Rows::rows_match( $label, $r->{ roles }, $expected_auth_roles, 'auth_roles_id', [ qw/role description/ ] );

    $label = 'roles update';

    my $user_role = $expected_auth_roles->[ 0 ];
    my $update_input = { auth_users_id => $search_user->{ auth_users_id }, roles => [ $user_role->{ role } ] };
    $r = MediaWords::Test::API::test_put( '/api/v2/users/update', $update_input );

    my $role_present = $db->query( <<SQL, $search_user->{ auth_users_id }, $user_role->{ auth_roles_id } )->hash();
        select * from auth_users_roles_map where auth_users_id = \$1 and auth_roles_id = \$2
SQL

    ok( $role_present, $label );

    $label = 'roles delete';

    $update_input = { auth_users_id => $search_user->{ auth_users_id }, roles => [] };
    $r = MediaWords::Test::API::test_put( '/api/v2/users/update', $update_input );

    $role_present = $db->query( <<SQL, $search_user->{ auth_users_id } )->hash();
        select * from auth_users_roles_map where auth_users_id = \$1
SQL

    ok( !$role_present, $label );

    $label = 'users/delete';

    my $delete_user = pop( @{ $expected_auth_users } );

    $r = MediaWords::Test::API::test_put( '/api/v2/users/delete', { auth_users_id => $delete_user->{ auth_users_id } } );

    ok( $r->{ success } == 1, "$label returned sucess" );

    my $user_exists = $db->find_by_id( 'auth_users', $delete_user->{ auth_users_id } );
    ok( !$user_exists, "$label user exists" );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_users( $db );

    done_testing();
}

main();
