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
use Test::More tests => 68;

use MediaWords::Test::API;
use MediaWords::Test::DB;

sub test_auth_register($)
{
    my ( $db ) = @_;

    my $email    = 'test@auth.register';
    my $password = 'authregister';

    # Register user
    {
        my $r = test_post(
            '/api/v2/auth/register',
            {
                email                   => $email,
                password                => $password,
                full_name               => 'Full Name',
                notes                   => '',
                subscribe_to_newsletter => 1,
                activation_url          => 'https://activate.com/',
            }
        );
        is( $r->{ 'success' }, 1 );

        # Confirm that we can't log in without activation
        eval { MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        ok( $@ );

        # Activate manually
        $db->query(
            <<SQL,
            UPDATE auth_users
            SET active = 't'
            WHERE email = ?
SQL
            $email
        );

        # Confirm that we still can't log due to unsuccessful login delay
        eval { MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        ok( $@ );

        # Imposed delay after unsuccessful login
        sleep( 2 );

        # Confirm that we can log in after the delay
        my $user;
        eval { $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        ok( !$@ );
        is( $user->email(), $email );

        # Confirm that user is subscribed to the newsletter
        my ( $subscribed ) = $db->query(
            <<SQL,
            SELECT subscribe_to_newsletter
            FROM auth_users
            WHERE email = ?
SQL
            $email
        )->flat;
        ok( $subscribed );
    }

    # Try registering duplicate user
    {
        my $expect_error = 1;
        my $r            = test_post(
            '/api/v2/auth/register',
            {
                email                   => $email,
                password                => $password,
                full_name               => 'Full Name',
                notes                   => '',
                subscribe_to_newsletter => 1,
                activation_url          => 'https://activate.com/',
            },
            $expect_error
        );
        ok( $r->{ 'error' } );
    }
}

sub test_auth_activate($)
{
    my ( $db ) = @_;

    my $email          = 'test@auth.activate';
    my $password       = 'authactivate';
    my $activation_url = 'http://activate.com/';

    # Add inactive user
    {
        {
            my $r = test_post(
                '/api/v2/auth/register',
                {
                    email                   => $email,
                    password                => $password,
                    full_name               => 'Full Name',
                    notes                   => '',
                    subscribe_to_newsletter => 1,
                    activation_url          => 'https://activate.com/',
                }
            );
            is( $r->{ 'success' }, 1 );
        }

        {
            # Confirm that we can't log in without activation
            my $expect_error = 1;
            my $login = test_post( '/api/v2/auth/login', { username => $email, password => $password }, $expect_error );
            ok( $login->{ 'error' } );
        }
    }

    # Imposed delay after unsuccessful login
    sleep( 2 );

    # Get activation token manually
    my $final_activation_url =
      MediaWords::DBI::Auth::Register::_generate_user_activation_token( $db, $email, $activation_url );

    my $final_activation_uri = URI->new( $final_activation_url );
    my $activation_token     = $final_activation_uri->query_param( 'activation_token' );
    ok( $activation_token );
    ok( length( $activation_token ) > 1 );

    # Activate user
    {
        my $r = test_post(
            '/api/v2/auth/activate',
            {
                email            => $email,
                activation_token => $activation_token,
            }
        );
        is( $r->{ 'success' },              1 );
        is( $r->{ 'profile' }->{ 'email' }, $email );
    }

    # Test logging in
    {
        my $r = test_post( '/api/v2/auth/login', { username => $email, password => $password } );
        is( $r->{ 'success' }, 1 );
    }

    # Try activating nonexistent user
    {
        my $expect_error = 1;
        my $r            = test_post(
            '/api/v2/auth/activate',
            {
                email            => 'totally_does_not_exist@gmail.com',
                activation_token => $activation_token,
            },
            $expect_error
        );
        ok( $r->{ 'error' } );
    }
}

# test auth/profile call
sub test_auth_profile($)
{
    my ( $db ) = @_;

    my $api_key = MediaWords::Test::API::get_test_api_key();

    my $expected_user = $db->query( <<SQL, $api_key )->hash;
        SELECT *
        FROM auth_users
            INNER JOIN auth_user_api_keys USING (auth_users_id)
            JOIN auth_user_limits USING (auth_users_id)
        WHERE auth_user_api_keys.api_key = \$1
          AND auth_user_api_keys.ip_address IS NULL
        LIMIT 1
SQL
    my $profile = test_get( "/api/v2/auth/profile" );

    for my $field ( qw/email auth_users_id weekly_request_items_limit notes active weekly_requests_limit/ )
    {
        is( $profile->{ $field }, $expected_user->{ $field }, "auth profile $field" );
    }
}

# test auth/login
sub test_auth_login($)
{
    my ( $db ) = @_;

    my $email    = 'test@auth.login';
    my $password = 'authlogin';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                        => $email,
            full_name                    => 'auth login',
            notes                        => '',
            role_ids                     => [ 1 ],
            active                       => 1,
            password                     => $password,
            password_repeat              => $password,
            activation_url               => '',             # user is active, no need for activation URL
            weekly_requests_limit        => 1000,
            weekly_requested_items_limit => 1000,
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    my $r = test_post( '/api/v2/auth/login', { username => $email, password => $password } );

    my $db_api_key = $db->query(
        <<SQL,
        SELECT *
        FROM auth_user_api_keys
        WHERE ip_address IS NOT NULL
          AND auth_users_id = (
            SELECT auth_users_id
            FROM auth_users
            WHERE email = ?
          )
        ORDER BY auth_user_api_keys_id DESC
        LIMIT 1
SQL
        $email
    )->hash;

    is( $r->{ api_key }, $db_api_key->{ api_key }, "'/api/v2/auth/login' API key" );
    is( $db_api_key->{ ip_address }, '127.0.0.1' );

    Readonly my $expect_error => 1;
    my $r_not_found = test_post( '/api/v2/auth/login', { username => $email, password => "$password FOO" }, $expect_error );
    ok( $r_not_found->{ error } =~ /was not found or password/i, "'/api/v2/auth/login' status for wrong password" );
}

# test deprecated auth/single
sub test_auth_single($)
{
    my ( $db ) = @_;

    my $email    = 'test@auth.single';
    my $password = 'authsingle';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                        => $email,
            full_name                    => 'auth single',
            notes                        => '',
            role_ids                     => [ 1 ],
            active                       => 1,
            password                     => $password,
            password_repeat              => $password,
            activation_url               => '',              # user is active, no need for activation URL
            weekly_requests_limit        => 1000,
            weekly_requested_items_limit => 1000,
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    my $r = test_get( '/api/v2/auth/single', { username => $email, password => $password } );

    my $db_api_key = $db->query(
        <<SQL,
        SELECT *
        FROM auth_user_api_keys
        WHERE ip_address IS NOT NULL
          AND auth_users_id = (
            SELECT auth_users_id
            FROM auth_users
            WHERE email = ?
          )
        ORDER BY auth_user_api_keys_id DESC
        LIMIT 1
SQL
        $email
    )->hash;

    is( $r->[ 0 ]->{ token }, $db_api_key->{ api_key }, "'/api/v2/auth/single' token (legacy)" );
    ok( !defined $r->[ 0 ]->{ api_key }, "'/api/v2/auth/single' api_key should be undefined" );
    is( $db_api_key->{ ip_address }, '127.0.0.1' );

    my $r_not_found = test_get( '/api/v2/auth/single', { username => $email, password => "$password FOO" } );
    is( $r_not_found->[ 0 ]->{ result }, 'not found', "'/api/v2/auth/single' status for wrong password" );
    ok( !defined $r_not_found->[ 0 ]->{ token },   "'/api/v2/auth/single' token is undefined" );
    ok( !defined $r_not_found->[ 0 ]->{ api_key }, "'/api/v2/auth/single' api_key should be undefined" );
}

# test auth/* calls
sub test_auth($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    test_auth_register( $db );
    test_auth_activate( $db );
    test_auth_profile( $db );
    test_auth_login( $db );
    test_auth_single( $db );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database( \&test_auth );
}

main();
