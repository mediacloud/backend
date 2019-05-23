use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Register;
use MediaWords::Util::Mail;

sub test_add_user($)
{
    my ( $db ) = @_;

    my $email     = 'test@user.login';
    my $password  = 'userlogin123';
    my $full_name = 'Test user login';

    # Add user
    {
        eval {
            MediaWords::DBI::Auth::Register::add_user(
                $db,
                MediaWords::DBI::Auth::User::NewUser->new(
                    email           => $email,
                    full_name       => $full_name,
                    notes           => 'Test test test',
                    role_ids        => [ 1 ],
                    active          => 1,
                    password        => $password,
                    password_repeat => $password,
                    activation_url  => '',                 # user is active, no need for activation URL
                )
            );
        };
        ok( !$@, "Unable to add user: $@" );

        # Test logging in
        my $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password );
        ok( $user );
        is( $user->email(),     $email );
        is( $user->full_name(), $full_name );
    }

    # Faulty input
    {
        eval { MediaWords::DBI::Auth::Register::add_user( $db, undef ); };
        ok( $@ );
    }

    # Existing user
    {
        eval {
            MediaWords::DBI::Auth::Register::add_user(
                $db,
                MediaWords::DBI::Auth::User::NewUser->new(
                    email           => $email,
                    full_name       => $full_name,
                    notes           => 'Test test test',
                    role_ids        => [ 1 ],
                    active          => 1,
                    password        => $password,
                    password_repeat => $password,
                    activation_url  => '',                 # user is active, no need for activation URL
                )
            );
        };
        ok( $@ );
    }

    # Existing user with uppercase email
    {
        eval {
            MediaWords::DBI::Auth::Register::add_user(
                $db,
                MediaWords::DBI::Auth::User::NewUser->new(
                    email           => uc( $email ),
                    full_name       => $full_name,
                    notes           => 'Test test test',
                    role_ids        => [ 1 ],
                    active          => 1,
                    password        => $password,
                    password_repeat => $password,
                    activation_url  => '',                 # user is active, no need for activation URL
                )
            );
        };
        ok( $@ );
    }

    # Invalid password
    {
        eval {
            MediaWords::DBI::Auth::Register::add_user(
                $db,
                MediaWords::DBI::Auth::User::NewUser->new(
                    email           => 'user123@email.com',
                    full_name       => $full_name,
                    notes           => 'Test test test',
                    role_ids        => [ 1 ],
                    active          => 1,
                    password        => 'abc',
                    password_repeat => 'def',
                    activation_url  => '',                    # user is active, no need for activation URL
                )
            );
        };
        ok( $@ );
    }

    # Nonexistent roles
    {
        eval {
            MediaWords::DBI::Auth::Register::add_user(
                $db,
                MediaWords::DBI::Auth::User::NewUser->new(
                    email           => 'user456@email.com',
                    full_name       => $full_name,
                    notes           => 'Test test test',
                    role_ids        => [ 42 ],
                    active          => 1,
                    password        => 'abc',
                    password_repeat => 'def',
                    activation_url  => '',                    # user is active, no need for activation URL
                )
            );
        };
        ok( $@ );
    }

    # Both the user is set as active and the activation URL is set
    {
        eval {
            MediaWords::DBI::Auth::Register::add_user(
                $db,
                MediaWords::DBI::Auth::User::NewUser->new(
                    email           => 'user789@email.com',
                    full_name       => $full_name,
                    notes           => 'Test test test',
                    role_ids        => [ 42 ],
                    active          => 1,
                    password        => 'abc',
                    password_repeat => 'def',
                    activation_url  => 'https://activate-user.com/activate',
                )
            );
        };
        ok( $@ );
    }

    # User is neither active not the activation URL is set
    {
        eval {
            MediaWords::DBI::Auth::Register::add_user(
                $db,
                MediaWords::DBI::Auth::User::NewUser->new(
                    email           => 'user784932@email.com',
                    full_name       => $full_name,
                    notes           => 'Test test test',
                    role_ids        => [ 42 ],
                    active          => 0,
                    password        => 'abc',
                    password_repeat => 'def',
                    activation_url  => '',
                )
            );
        };
        ok( $@ );
    }
}

sub main
{
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    my $db = MediaWords::DB::connect_to_db();

    test_add_user( $db );

    done_testing();
}

main();
