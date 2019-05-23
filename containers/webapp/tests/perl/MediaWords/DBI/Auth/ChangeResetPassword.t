use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Readonly;
use Test::More tests => 42;
use Test::Deep;
use URI;
use URI::QueryParam;

use MediaWords::DB;
use MediaWords::DBI::Auth::ChangePassword;
use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Register;
use MediaWords::DBI::Auth::ResetPassword;
use MediaWords::Util::Mail;

sub test_change_password($)
{
    my ( $db ) = @_;

    my $email     = 'test@user.login';
    my $password  = 'userlogin123';
    my $full_name = 'Test user login';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => $full_name,
            notes           => 'Test test test',
            role_ids        => [ 1 ],
            active          => 1,
            password        => $password,
            password_repeat => $password,
            activation_url  => '',                 # user is active, no need for activation URL
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

    # Change password
    my $new_password            = 'this is a new password to set';
    my $do_not_inform_via_email = 1;
    MediaWords::DBI::Auth::ChangePassword::change_password( $db, $email, $new_password, $new_password,
        $do_not_inform_via_email );

    # Unsuccessful login with old password
    {
        eval { MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        ok( $@ );
    }

    # Imposed delay after unsuccessful login
    sleep( 2 );

    # Successful login with new password
    {
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $new_password );
        ok( $user );
        is( $user->email(),     $email );
        is( $user->full_name(), $full_name );
    }

    # Changing for nonexistent user
    {
        eval { MediaWords::DBI::Auth::ChangePassword::change_password( $db, 'does@not.exist', 'x', 'x' ); };
        ok( $@ );
    }

    # Passwords don't match
    {
        eval { MediaWords::DBI::Auth::ChangePassword::change_password( $db, $email, 'x', 'y' ); };
        ok( $@ );
    }
}

sub test_change_password_with_old_password($)
{
    my ( $db ) = @_;

    my $email     = 'test@user.login';
    my $password  = 'userlogin123';
    my $full_name = 'Test user login';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => $full_name,
            notes           => 'Test test test',
            role_ids        => [ 1 ],
            active          => 1,
            password        => $password,
            password_repeat => $password,
            activation_url  => '',                 # user is active, no need for activation URL
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

    # Change password
    my $new_password = 'this is a new password to set';
    MediaWords::DBI::Auth::ChangePassword::change_password_with_old_password( $db, $email, $password, $new_password,
        $new_password );

    # Unsuccessful login with old password
    {
        eval { MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        ok( $@ );
    }

    # Imposed delay after unsuccessful login
    sleep( 2 );

    # Successful login with new password
    {
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $new_password );
        ok( $user );
        is( $user->email(),     $email );
        is( $user->full_name(), $full_name );
    }

    # Incorrect password
    {
        eval {
            MediaWords::DBI::Auth::ChangePassword::change_password_with_old_password( $db, $email, 'incorrect password',
                'x', 'x' );
        };
        ok( $@ );
    }

    # Changing for nonexistent user
    {
        eval {
            MediaWords::DBI::Auth::ChangePassword::change_password_with_old_password( $db, 'does@not.exist', $new_password,
                'x', 'x' );
        };
        ok( $@ );
    }

    # Passwords don't match
    {
        eval {
            MediaWords::DBI::Auth::ChangePassword::change_password_with_old_password( $db, $email, $new_password, 'x', 'y' );
        };
        ok( $@ );
    }
}

sub test_change_password_with_reset_token($)
{
    my ( $db ) = @_;

    my $email     = 'test@user.login';
    my $password  = 'userlogin123';
    my $full_name = 'Test user login';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => $full_name,
            notes           => 'Test test test',
            role_ids        => [ 1 ],
            active          => 1,
            password        => $password,
            password_repeat => $password,
            activation_url  => '',                 # user is active, no need for activation URL
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

    # Make sure password reset token is not set
    {
        my ( $password_reset_token_hash ) = $db->query(
            <<SQL,
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = ?
SQL
            $email
        )->flat;
        ok( !$password_reset_token_hash );
    }

    # Send password reset link
    my $password_reset_url = 'https://reset-password.com/reset';
    my $final_password_reset_url =
      MediaWords::DBI::Auth::ResetPassword::_generate_password_reset_token( $db, $email, $password_reset_url );
    ok( $final_password_reset_url );
    like( $final_password_reset_url, qr/\Q$password_reset_url\E/ );

    my $final_password_reset_uri = URI->new( $final_password_reset_url );
    ok( $final_password_reset_uri->query_param( 'email' ) . '' );
    my $password_reset_token = $final_password_reset_uri->query_param( 'password_reset_token' );
    ok( $password_reset_token );
    ok( length( $password_reset_token ) > 1 );

    # Make sure password reset token is set
    {
        my ( $password_reset_token_hash ) = $db->query(
            <<SQL,
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = ?
SQL
            $email
        )->flat;
        ok( $password_reset_token_hash );
        ok( length( $password_reset_token_hash ) > 1 );
    }

    # Change password
    my $new_password = 'this is a new password to set';
    MediaWords::DBI::Auth::ChangePassword::change_password_with_reset_token( $db, $email, $password_reset_token,
        $new_password, $new_password );

    # Make sure password reset token is not set
    {
        my ( $password_reset_token_hash ) = $db->query(
            <<SQL,
            SELECT password_reset_token_hash
            FROM auth_users
            WHERE email = ?
SQL
            $email
        )->flat;
        ok( !$password_reset_token_hash );
    }

    # Unsuccessful login with old password
    {
        eval { MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
        ok( $@ );
    }

    # Imposed delay after unsuccessful login
    sleep( 2 );

    # Successful login with new password
    {
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $new_password );
        ok( $user );
        is( $user->email(),     $email );
        is( $user->full_name(), $full_name );
    }

    # Incorrect password reset token
    {
        MediaWords::DBI::Auth::ResetPassword::_generate_password_reset_token( $db, $email, $password_reset_url );
        eval {
            MediaWords::DBI::Auth::ChangePassword::change_password_with_reset_token( $db, $email,
                'incorrect password reset token',
                'x', 'x' );
        };
        ok( $@ );
    }

    # Changing for nonexistent user
    {
        eval {
            MediaWords::DBI::Auth::ChangePassword::change_password_with_reset_token( $db, 'does@not.exist',
                $password_reset_token, 'x', 'x' );
        };
        ok( $@ );
    }

    # Passwords don't match
    {
        my $final_password_reset_url =
          MediaWords::DBI::Auth::ResetPassword::_generate_password_reset_token( $db, $email, $password_reset_url );
        my $final_password_reset_uri = URI->new( $final_password_reset_url );
        my $password_reset_token     = $final_password_reset_uri->query_param( 'password_reset_token' );

        eval {
            MediaWords::DBI::Auth::ChangePassword::change_password_with_reset_token( $db, $email, $password_reset_token,
                'x', 'y' );
        };
        ok( $@ );
    }
}

sub test_send_password_reset_token($)
{
    my ( $db ) = @_;

    my $email               = 'test@user.login';
    my $password            = 'userlogin123';
    my $password_reset_link = 'http://password-reset.com/';

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => 'Test user login',
            notes           => 'Test test test',
            role_ids        => [ 1 ],
            active          => 1,
            password        => $password,
            password_repeat => $password,
            activation_url  => '',                  # user is active, no need for activation URL
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    # Existing user
    MediaWords::DBI::Auth::ResetPassword::send_password_reset_token( $db, $email, $password_reset_link );

    # Nonexisting user (call shouldn't fail because we don't want to reveal
    # which users are in the system so we pretend that we've sent the email)
    MediaWords::DBI::Auth::ResetPassword::send_password_reset_token( $db, 'does@not.exist', $password_reset_link );
}

sub main
{
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    my $db = MediaWords::DB::connect_to_db();

    test_change_password( $db );
    test_change_password_with_old_password( $db );
    test_change_password_with_reset_token( $db );
    test_send_password_reset_token( $db );
}

main();
