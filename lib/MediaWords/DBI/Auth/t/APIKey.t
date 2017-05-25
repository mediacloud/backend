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
use Test::More tests => 28;
use Test::Deep;

use MediaWords::Test::DB;

use MediaWords::DBI::Auth::APIKey;
use MediaWords::DBI::Auth::Register;

sub test_user_for_api_key($)
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

    # Get sample API keys
    my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password );
    ok( $user );
    my $global_api_key = $user->global_api_key();
    ok( $global_api_key );
    ok( length( $global_api_key ) > 1 );

    my $per_ip_api_key =
      MediaWords::DBI::Auth::Login::login_with_email_password_get_ip_api_key( $db, $email, $password, $ip_address );
    ok( $per_ip_api_key );
    ok( length( $per_ip_api_key ) > 1 );

    isnt( $global_api_key, $per_ip_api_key );

    {
        # Non-existent API key
        eval { MediaWords::DBI::Auth::APIKey::user_for_api_key( $db, 'Non-existent API key', $ip_address ); };
        ok( $@ );
    }

    {
        # Global API key
        my $api_key_user = MediaWords::DBI::Auth::APIKey::user_for_api_key( $db, $global_api_key, $ip_address );
        ok( $api_key_user );
        is( $api_key_user->email(),          $email );
        is( $api_key_user->global_api_key(), $global_api_key );
    }

    {
        # Per-IP API key
        my $api_key_user = MediaWords::DBI::Auth::APIKey::user_for_api_key( $db, $per_ip_api_key, $ip_address );
        ok( $api_key_user );
        is( $api_key_user->email(), $email );
    }
}

sub test_regenerate_api_key($)
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

    # Get sample API keys
    my ( $before_global_api_key, $before_per_ip_api_key );
    {
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password );
        ok( $user );
        $before_global_api_key = $user->global_api_key();
        ok( $before_global_api_key );
        ok( length( $before_global_api_key ) > 1 );

        $before_per_ip_api_key =
          MediaWords::DBI::Auth::Login::login_with_email_password_get_ip_api_key( $db, $email, $password, $ip_address );
        ok( $before_per_ip_api_key );
        ok( length( $before_per_ip_api_key ) > 1 );

        isnt( $before_global_api_key, $before_per_ip_api_key );
    }

    # Regenerate API key, purge per-IP API keys
    MediaWords::DBI::Auth::APIKey::regenerate_api_key( $db, $email );

    # Get sample API keys again
    my ( $after_global_api_key, $after_per_ip_api_key );
    {
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password );
        ok( $user );
        $after_global_api_key = $user->global_api_key();
        ok( $after_global_api_key );
        ok( length( $after_global_api_key ) > 1 );

        $after_per_ip_api_key =
          MediaWords::DBI::Auth::Login::login_with_email_password_get_ip_api_key( $db, $email, $password, $ip_address );
        ok( $after_per_ip_api_key );
        ok( length( $after_per_ip_api_key ) > 1 );

        isnt( $after_global_api_key, $after_per_ip_api_key );
    }

    # Make sure API keys are different
    isnt( $before_global_api_key, $after_global_api_key );
    isnt( $before_per_ip_api_key, $after_per_ip_api_key );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;
            test_user_for_api_key( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;
            test_regenerate_api_key( $db );
        }
    );
}

main();
