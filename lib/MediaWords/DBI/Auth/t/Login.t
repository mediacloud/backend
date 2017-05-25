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
use Test::More tests => 19;
use Test::Deep;

use MediaWords::Test::DB;

use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Register;

sub test_login_with_email_password($)
{
    my ( $db ) = @_;

    my $email     = 'test@user.login';
    my $password  = 'userlogin123';
    my $full_name = 'Test user login';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                        => $email,
            full_name                    => $full_name,
            notes                        => 'Test test test',
            role_ids                     => [ 1 ],
            active                       => 1,
            password                     => $password,
            password_repeat              => $password,
            activation_url               => '',                 # user is active, no need for activation URL
            weekly_requests_limit        => 123,
            weekly_requested_items_limit => 456,
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    # Successful login
    {
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password );
        ok( $user );
        is( $user->email(),     $email );
        is( $user->full_name(), $full_name );
    }

    # Unsuccessful login
    {
        eval { MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, 'wrong password' ); };
        ok( $@ );
    }

    # Subsequent login attempt after a failed one should be delayed by 1 second
    {
        eval { MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        ok( $@ );
    }

    # Successful login after waiting out the delay
    {
        sleep( 2 );
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password );
        ok( $user );
        is( $user->email(),     $email );
        is( $user->full_name(), $full_name );
    }
}

sub test_login_with_email_password_get_ip_api_key($)
{
    my ( $db ) = @_;

    my $email      = 'test@user.login';
    my $password   = 'userlogin123';
    my $full_name  = 'Test user login';
    my $ip_address = '1.2.3.4';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                        => $email,
            full_name                    => $full_name,
            notes                        => 'Test test test',
            role_ids                     => [ 1 ],
            active                       => 1,
            password                     => $password,
            password_repeat              => $password,
            activation_url               => '',                 # user is active, no need for activation URL
            weekly_requests_limit        => 123,
            weekly_requested_items_limit => 456,
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    # Get per-IP API key
    my $api_key =
      MediaWords::DBI::Auth::Login::login_with_email_password_get_ip_api_key( $db, $email, $password, $ip_address );
    ok( $api_key );
    ok( length( $api_key ) > 1 );

    # Get it again for the same IP, make sure the same one gets returned
    my $api_key_2 =
      MediaWords::DBI::Auth::Login::login_with_email_password_get_ip_api_key( $db, $email, $password, $ip_address );
    ok( $api_key_2 );
    ok( length( $api_key_2 ) > 1 );
    is( $api_key, $api_key_2 );

    # Log in from different IP address, ensure that a different API key is returned
    my $api_key_different_ip =
      MediaWords::DBI::Auth::Login::login_with_email_password_get_ip_api_key( $db, $email, $password, '2.3.4.5' );
    ok( $api_key_different_ip );
    ok( length( $api_key_different_ip ) > 1 );
    isnt( $api_key,   $api_key_different_ip );
    isnt( $api_key_2, $api_key_different_ip );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;
            test_login_with_email_password( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;
            test_login_with_email_password_get_ip_api_key( $db );
        }
    );
}

main();
