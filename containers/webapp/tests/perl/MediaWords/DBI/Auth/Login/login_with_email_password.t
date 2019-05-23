use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Register;
use MediaWords::Util::Mail;

sub test_login_with_email_password($)
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

    # Inactive user
    {
        my $inactive_user_email = 'inactive@user.com';

        eval {
            my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
                email           => $inactive_user_email,
                full_name       => $full_name,
                notes           => 'Test test test',
                role_ids        => [ 1 ],
                active          => 0,
                password        => $password,
                password_repeat => $password,
                activation_url  => 'https://activate.com/activate',
            );

            MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
        };
        ok( !$@, "Unable to add user: $@" );

        eval { MediaWords::DBI::Auth::Login::login_with_email_password( $db, $inactive_user_email, $password ); };
        my $error_message = $@;
        ok( $error_message );

        # Make sure the error message explicitly states that login failed due to user not being active
        like( $error_message, qr/not active/i );
    }
}
sub main
{
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    my $db = MediaWords::DB::connect_to_db();

    test_login_with_email_password( $db );

    done_testing();
}

main();
