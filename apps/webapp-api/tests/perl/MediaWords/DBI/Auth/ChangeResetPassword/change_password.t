use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Auth::ChangePassword;
use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Register;
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

sub main
{
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    my $db = MediaWords::DB::connect_to_db();

    test_change_password( $db );

    done_testing();
}

main();
