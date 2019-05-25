use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Auth::Register;
use MediaWords::DBI::Auth::ResetPassword;
use MediaWords::Util::Mail;

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

    test_send_password_reset_token( $db );

    done_testing();
}

main();
