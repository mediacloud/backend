use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use HTTP::HashServer;
use Readonly;
use Test::More tests => 20;
use Test::Deep;

use MediaWords::Test::API;
use MediaWords::Test::DB;

# test auth/profile call
sub test_auth_profile($)
{
    my ( $db ) = @_;

    my $api_key = MediaWords::Test::API::get_test_api_key();

    my $expected_user = $db->query( <<SQL, $api_key )->hash;
        SELECT *
        FROM auth_users au
            JOIN auth_user_limits using ( auth_users_id )
        WHERE api_key = \$1
SQL
    my $profile = test_get( "/api/v2/auth/profile" );

    for my $field ( qw/email auth_users_id weekly_request_items_limit notes active weekly_requests_limit/ )
    {
        is( $profile->{ $field }, $expected_user->{ $field }, "auth profile $field" );
    }
}

# test auth/single
sub test_auth_single($)
{
    my ( $db ) = @_;

    my $label = "auth/single";

    my $email    = 'test@auth.single';
    my $password = 'authsingle';

    eval { MediaWords::DBI::Auth::add_user( $db, $email, 'auth single', '', [ 1 ], 1, $password, $password, 1000, 1000 ); };
    ok( !$@, "Unable to add user: $@" );

    my $r = test_get( '/api/v2/auth/single', { username => $email, password => $password } );

    my $db_api_key = $db->query( <<SQL )->hash;
        SELECT *
        FROM auth_user_ip_address_api_keys
        ORDER BY auth_user_ip_address_api_keys_id DESC
        LIMIT 1
SQL

    is( $r->{ token },   $db_api_key->{ api_key }, "$label token (legacy)" );
    is( $r->{ api_key }, $db_api_key->{ api_key }, "$label API key" );
    is( $db_api_key->{ ip_address }, '127.0.0.1' );

    Readonly my $expect_error => 1;
    my $r_not_found = test_get( '/api/v2/auth/single', { username => $email, password => "$password FOO" }, $expect_error );
    ok( $r_not_found->{ error } =~ /was not found or password/i, "$label status for wrong password" );
}

# test auth/* calls
sub test_auth($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    test_auth_profile( $db );
    test_auth_single( $db );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_auth );
}

main();
