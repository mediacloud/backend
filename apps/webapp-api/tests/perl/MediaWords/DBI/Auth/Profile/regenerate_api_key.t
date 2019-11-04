use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Profile;
use MediaWords::DBI::Auth::Register;
use MediaWords::Util::Mail;

sub test_regenerate_api_key($)
{
    my ( $db ) = @_;

    my $email      = 'test@user.login';
    my $password   = 'userlogin123';
    my $full_name  = 'Test user login';
    my $ip_address = '1.2.3.4';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => $full_name,
            notes           => 'Test test test',
            role_ids        => [ 1 ],
            active          => 1,
            has_consented   => 1,
            password        => $password,
            password_repeat => $password,
            activation_url  => '',                 # user is active, no need for activation URL
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    # Get sample API keys
    my ( $before_global_api_key, $before_per_ip_api_key );
    {
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password, $ip_address );
        ok( $user );
        $before_global_api_key = $user->global_api_key();
        ok( $before_global_api_key );
        ok( length( $before_global_api_key ) > 1 );

        $before_per_ip_api_key = $user->api_key_for_ip_address( $ip_address );
        ok( $before_per_ip_api_key );
        ok( length( $before_per_ip_api_key ) > 1 );

        isnt( $before_global_api_key, $before_per_ip_api_key );
    }

    # Regenerate API key, purge per-IP API keys
    MediaWords::DBI::Auth::Profile::regenerate_api_key( $db, $email );

    # Get sample API keys again
    my ( $after_global_api_key, $after_per_ip_api_key );
    {
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password, $ip_address );
        ok( $user );
        $after_global_api_key = $user->global_api_key();
        ok( $after_global_api_key );
        ok( length( $after_global_api_key ) > 1 );

        $after_per_ip_api_key = $user->api_key_for_ip_address( $ip_address );
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
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    my $db = MediaWords::DB::connect_to_db();

    test_regenerate_api_key( $db );

    done_testing();
}

main();
