use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;
use URI;
use URI::QueryParam;

use MediaWords::DB;
use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Register;
use MediaWords::Util::Mail;

sub test_activate_user_via_token($)
{
    my ( $db ) = @_;

    my $email          = 'test@user.login';
    my $password       = 'userlogin123';
    my $full_name      = 'Test user login';
    my $activation_url = 'https://activate.com/activate';

    # Add inactive user
    {
        eval {
            MediaWords::DBI::Auth::Register::add_user(
                $db,
                MediaWords::DBI::Auth::User::NewUser->new(
                    email           => $email,
                    full_name       => $full_name,
                    notes           => 'Test test test',
                    role_ids        => [ 1 ],
                    active          => 0,                  # not active, needs to be activated
                    has_consented   => 1,
                    password        => $password,
                    password_repeat => $password,
                    activation_url  => $activation_url,
                )
            );
        };
        ok( !$@, "Unable to add user: $@" );

        # Test logging in
        eval { MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        my $error_message = $@;
        ok( $error_message );

        # Make sure the error message explicitly states that login failed due to user not being active
        like( $error_message, qr/not active/i );
    }

    # Make sure activation token is set
    {
        my ( $activation_token_hash ) = $db->query(
            <<SQL,
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = ?
SQL
            $email
        )->flat;
        ok( $activation_token_hash );
        ok( length( $activation_token_hash ) > 1 );
    }

    # Send password reset link
    my $final_activation_url =
      MediaWords::DBI::Auth::Register::_generate_user_activation_token( $db, $email, $activation_url );
    ok( $final_activation_url );
    like( $final_activation_url, qr/\Qactivation_token\E/ );

    my $final_activation_uri = URI->new( $final_activation_url );
    ok( $final_activation_uri->query_param( 'email' ) . '' );
    my $activation_token = $final_activation_uri->query_param( 'activation_token' );
    ok( $activation_token );
    ok( length( $activation_token ) > 1 );

    # Make sure activation token is (still) set
    {
        my ( $activation_token_hash ) = $db->query(
            <<SQL,
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = ?
SQL
            $email
        )->flat;
        ok( $activation_token_hash );
        ok( length( $activation_token_hash ) > 1 );
    }

    # Activate user
    MediaWords::DBI::Auth::Register::activate_user_via_token( $db, $email, $activation_token );

    # Imposed delay after unsuccessful login
    sleep( 2 );

    # Test logging in
    {
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password );
        ok( $user );
        is( $user->email(),     $email );
        is( $user->full_name(), $full_name );
    }

    # Make sure activation token is not set anymore
    {
        my ( $activation_token_hash ) = $db->query(
            <<SQL,
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = ?
SQL
            $email
        )->flat;
        ok( !$activation_token_hash );
    }

    # Incorrect activation token
    {
        MediaWords::DBI::Auth::Register::_generate_user_activation_token( $db, $email, $activation_url );
        eval { MediaWords::DBI::Auth::Register::activate_user_via_token( $db, $email, 'incorrect activation token' ); };
        ok( $@ );
    }

    # Activating nonexistent user
    {
        my $final_activation_url =
          MediaWords::DBI::Auth::Register::_generate_user_activation_token( $db, $email, $activation_url );
        my $final_activation_uri = URI->new( $final_activation_url );
        my $activation_token     = $final_activation_uri->query_param( 'activation_token' );
        eval { MediaWords::DBI::Auth::Register::activate_user_via_token( $db, 'does@not.exist', $activation_token ); };
        ok( $@ );
    }
}

sub main
{
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    my $db = MediaWords::DB::connect_to_db();

    test_activate_user_via_token( $db );

    done_testing();
}

main();
