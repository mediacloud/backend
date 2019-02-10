use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More tests => 150;
use Test::Deep;

use URI;
use URI::QueryParam;

use MediaWords::Test::API;
use MediaWords::Test::DB;

use MediaWords::DBI::Auth;
use MediaWords::Util::Mail;

sub test_register($)
{
    my ( $db ) = @_;

    my $email    = 'test@auth.register';
    my $password = 'authregister';

    # Register user
    {
        my $r = MediaWords::Test::API::test_post(
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

        # Confirm that we can log in after activation
        my $user;
        eval { $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        ok( !$@ );
        is( $user->email(), $email );

        # Confirm that user is subscribed to the newsletter
        my ( $subscribed ) = $db->query(
            <<SQL,
            SELECT 1
            FROM auth_users_subscribe_to_newsletter
                INNER JOIN auth_users
                    ON auth_users_subscribe_to_newsletter.auth_users_id = auth_users.auth_users_id
            WHERE auth_users.email = ?
SQL
            $email
        )->flat;
        ok( $subscribed );
    }

    # Try registering duplicate user
    {
        my $expect_error = 1;
        my $r            = MediaWords::Test::API::test_post(
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

sub test_activate($)
{
    my ( $db ) = @_;

    my $email          = 'test@auth.activate';
    my $password       = 'authactivate';
    my $activation_url = 'http://activate.com/';

    # Add inactive user
    {
        {
            my $r = MediaWords::Test::API::test_post(
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
            my $login = MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => $password },
                $expect_error );
            ok( $login->{ 'error' } );
        }
    }

    # Get activation token manually
    my $final_activation_url =
      MediaWords::DBI::Auth::Register::_generate_user_activation_token( $db, $email, $activation_url );

    my $final_activation_uri = URI->new( $final_activation_url );
    my $activation_token     = $final_activation_uri->query_param( 'activation_token' );
    ok( $activation_token );
    ok( length( $activation_token ) > 1 );

    # Activate user
    {
        my $r = MediaWords::Test::API::test_post(
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
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => $password } );
        is( $r->{ 'success' }, 1 );
    }

    # Try activating nonexistent user
    {
        my $expect_error = 1;
        my $r            = MediaWords::Test::API::test_post(
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

sub test_resend_activation_link($)
{
    my ( $db ) = @_;

    my $email          = 'test@auth.reactivate';
    my $password       = 'authreactivate';
    my $activation_url = 'https://activate.com/';

    # Register user
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/register',
            {
                email                   => $email,
                password                => $password,
                full_name               => 'Full Name',
                notes                   => '',
                subscribe_to_newsletter => 1,
                activation_url          => $activation_url,
            }
        );
        is( $r->{ 'success' }, 1 );
    }

    # Resend activation link
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/resend_activation_link',
            {
                email          => $email,
                activation_url => $activation_url,
            }
        );
        is( $r->{ 'success' }, 1 );
    }

    # Try sending for nonexistent user (should not fail in order to not reveal
    # whether or not a particular user exists)
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/resend_activation_link',
            {
                email          => 'totally_does_not_exist@gmail.com',
                activation_url => $activation_url,
            }
        );
        is( $r->{ 'success' }, 1 );
    }
}

sub test_send_password_reset_link($)
{
    my ( $db ) = @_;

    my $email              = 'test@auth.sendpasswordresetlink';
    my $password           = 'sendpasswordresetlink';
    my $password_reset_url = 'https://password-reset.com/';

    # Register user
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/register',
            {
                email                   => $email,
                password                => $password,
                full_name               => 'Full Name',
                notes                   => '',
                subscribe_to_newsletter => 1,
                activation_url          => 'http://activation.com/',
            }
        );
        is( $r->{ 'success' }, 1 );
    }

    # Resend password reset link
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/send_password_reset_link',
            {
                email              => $email,
                password_reset_url => $password_reset_url,
            }
        );
        is( $r->{ 'success' }, 1 );
    }

    # Try sending for nonexistent user (should not fail in order to not reveal
    # whether or not a particular user exists)
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/send_password_reset_link',
            {
                email              => 'totally_does_not_exist@gmail.com',
                password_reset_url => $password_reset_url,
            }
        );
        is( $r->{ 'success' }, 1 );
    }
}

sub test_reset_password($)
{
    my ( $db ) = @_;

    my $email              = 'test@auth.reset_password';
    my $password           = 'authresetpassword';
    my $password_reset_url = 'http://reset-password.com/';

    # Add active user
    my $role_ids = MediaWords::DBI::Auth::Roles::default_role_ids( $db );
    MediaWords::DBI::Auth::Register::add_user(
        $db,
        MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => 'Full Name',
            notes           => '',
            role_ids        => $role_ids,
            active          => 1,
            password        => $password,
            password_repeat => $password,
        )
    );

    # Test logging in
    {
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => $password } );
        is( $r->{ 'success' }, 1 );
    }

    # Send password reset link
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/send_password_reset_link',
            {
                email              => $email,
                password_reset_url => $password_reset_url,
            }
        );
        is( $r->{ 'success' }, 1 );
    }

    # Get activation token manually
    my $final_password_reset_url =
      MediaWords::DBI::Auth::ResetPassword::_generate_password_reset_token( $db, $email, $password_reset_url );

    my $final_password_reset_uri = URI->new( $final_password_reset_url );
    my $password_reset_token     = $final_password_reset_uri->query_param( 'password_reset_token' );
    ok( $password_reset_token );
    ok( length( $password_reset_token ) > 1 );

    my $new_password = 'totally new password';

    # Reset user's password
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/reset_password',
            {
                email                => $email,
                password_reset_token => $password_reset_token,
                new_password         => $new_password,
            }
        );
        is( $r->{ 'success' }, 1 );
    }

    # Test logging in
    {
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => $new_password } );
        is( $r->{ 'success' }, 1 );
    }
}

# test auth/profile call
sub test_profile($)
{
    my ( $db ) = @_;

    my $api_key = MediaWords::Test::API::get_test_api_key();

    my $ip_address = '127.0.0.1';

    my $expected_profile = MediaWords::DBI::Auth::Login::login_with_api_key( $db, $api_key, $ip_address );
    ok( $expected_profile );
    is( $expected_profile->global_api_key(), $api_key );

    # We expect global API key to be returned
    my $expected_api_key = $expected_profile->global_api_key();
    ok( $expected_api_key );

    my $actual_profile = MediaWords::Test::API::test_get( '/api/v2/auth/profile' );
    ok( $actual_profile );

    is( $actual_profile->{ email },     $expected_profile->email() );
    is( $actual_profile->{ full_name }, $expected_profile->full_name() );
    is( $actual_profile->{ api_key },   $expected_api_key );
    is( $actual_profile->{ notes },     $expected_profile->notes() );

    # Looks like ISO 8601 date?
    like( $actual_profile->{ created_date }, qr/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$/i );

    is( $actual_profile->{ active }, $expected_profile->active() );
    cmp_deeply( $actual_profile->{ auth_roles }, $expected_profile->role_names() );
    is( $actual_profile->{ limits }->{ weekly }->{ requests }->{ used },  $expected_profile->weekly_requests_sum() );
    is( $actual_profile->{ limits }->{ weekly }->{ requests }->{ limit }, $expected_profile->weekly_requests_limit() );
    is( $actual_profile->{ limits }->{ weekly }->{ requested_items }->{ used },
        $expected_profile->weekly_requested_items_sum() );
    is( $actual_profile->{ limits }->{ weekly }->{ requested_items }->{ limit },
        $expected_profile->weekly_requested_items_limit() );
}

sub test_login($)
{
    my ( $db ) = @_;

    {
        my $email    = 'test@auth.login';
        my $password = 'authlogin';

        eval {

            my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
                email           => $email,
                full_name       => 'auth login',
                notes           => '',
                role_ids        => [ 1 ],
                active          => 1,
                password        => $password,
                password_repeat => $password,
                activation_url  => '',             # user is active, no need for activation URL
            );

            MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
        };
        ok( !$@, "Unable to add user: $@" );

        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => $password } );
        is( $r->{ success }, 1 );

        my $db_api_key = $db->query(
            <<SQL,
            SELECT *
            FROM auth_user_api_keys
            WHERE ip_address IS NULL
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

        is( $r->{ profile }->{ api_key }, $db_api_key->{ api_key }, "'/api/v2/auth/login' API key" );

        Readonly my $expect_error => 1;
        my $r_not_found =
          MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => "$password FOO" },
            $expect_error );
        ok( $r_not_found->{ error } =~ /was not found or password/i,
            "'/api/v2/auth/login' status for wrong password: " . $r_not_found->{ error } );
    }

    # Inactive user
    {
        my $email    = 'test@auth.logininactive';
        my $password = 'authlogininactive';

        eval {

            my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
                email           => $email,
                full_name       => 'auth login',
                notes           => '',
                role_ids        => [ 1 ],
                active          => 0,
                password        => $password,
                password_repeat => $password,
                activation_url  => 'https://activate.com/activate.php',
            );

            MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
        };
        ok( !$@, "Unable to add user: $@" );

        my $expect_error = 1;
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => $password },
            $expect_error );
        ok( $r->{ error } );

        # Make sure the error message explicitly states that login failed due to user not being active
        like( $r->{ error }, qr/not active/i );
    }
}

sub test_change_password($)
{
    my ( $db ) = @_;

    my $email    = 'test@auth.change_password';
    my $password = 'auth_change_password';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => 'auth change_password',
            notes           => '',
            role_ids        => [ 1 ],
            active          => 1,
            password        => $password,
            password_repeat => $password,
            activation_url  => '',                       # user is active, no need for activation URL
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    # Test whether we can log in with old password
    my $api_key;
    {
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => $password } );
        is( $r->{ success }, 1 );
        $api_key = $r->{ profile }->{ api_key };
        ok( $api_key );
    }

    my $new_password = 'this is a brand new password';

    # Change password
    {
        my $r = MediaWords::Test::API::test_post(
            '/api/v2/auth/change_password?key=' . $api_key,
            {
                old_password => $password,
                new_password => $new_password,
            }
        );
        is( $r->{ 'success' }, 1 );
    }

    # Test whether we can log in with new password
    {
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => $new_password } );
        is( $r->{ success }, 1 );
        $api_key = $r->{ profile }->{ api_key };
        ok( $api_key );
    }
}

sub test_reset_api_key($)
{
    my ( $db ) = @_;

    my $email    = 'test@auth.reset_api_key';
    my $password = 'auth_reset_api_key';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => 'auth reset_api_key',
            notes           => '',
            role_ids        => [ 1 ],
            active          => 1,
            password        => $password,
            password_repeat => $password,
            activation_url  => '',                     # user is active, no need for activation URL
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    # Get API key
    my $api_key;
    {
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/login', { email => $email, password => $password } );
        is( $r->{ success }, 1 );
        $api_key = $r->{ profile }->{ api_key };
        ok( $api_key );
    }

    # Test whether we can use old API key
    {
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/profile?key=' . $api_key, {} );
        is( $r->{ 'email' },   $email );
        is( $r->{ 'api_key' }, $api_key );
    }

    # Reset API key
    my $new_api_key;
    {
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/reset_api_key?key=' . $api_key, {} );
        is( $r->{ 'success' }, 1 );
        $new_api_key = $r->{ profile }->{ api_key };
    }

    # Test whether we can use new API key
    {
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/profile?key=' . $new_api_key, {} );
        is( $r->{ 'email' },   $email );
        is( $r->{ 'api_key' }, $new_api_key );
    }

    # Ensure that the old API key is invalid
    {
        my $expect_error = 1;
        my $r = MediaWords::Test::API::test_post( '/api/v2/auth/profile?key=' . $api_key, {}, $expect_error );
        ok( $r->{ 'error' } );
    }
}

# test auth/* calls
sub test_auth($)
{
    my ( $db ) = @_;

    MediaWords::Test::API::setup_test_api_key( $db );

    test_register( $db );
    test_activate( $db );
    test_resend_activation_link( $db );
    test_send_password_reset_link( $db );
    test_reset_password( $db );
    test_profile( $db );
    test_login( $db );
    test_change_password( $db );
    test_reset_api_key( $db );
}

sub main
{
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    MediaWords::Test::DB::test_on_test_database( \&test_auth );
}

main();
