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
use Test::More tests => 21;
use Test::Deep;

use MediaWords::Test::DB;

use MediaWords::DBI::Auth::Profile;
use MediaWords::DBI::Auth::Register;

sub test_user_info($)
{
    my ( $db ) = @_;

    my $email                        = 'test@user.info';
    my $full_name                    = 'Test user info';
    my $notes                        = 'Test test test';
    my $weekly_requests_limit        = 123;
    my $weekly_requested_items_limit = 456;

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                        => $email,
            full_name                    => $full_name,
            notes                        => $notes,
            role_ids                     => [ 1 ],
            active                       => 1,
            password                     => 'userinfo',
            password_repeat              => 'userinfo',
            activation_url               => '',                              # user is active, no need for activation URL
            weekly_requests_limit        => $weekly_requests_limit,
            weekly_requested_items_limit => $weekly_requested_items_limit,
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    my $user = MediaWords::DBI::Auth::Profile::user_info( $db, $email );

    is( $user->email(),                        $email );
    is( $user->full_name(),                    $full_name );
    is( $user->notes(),                        $notes );
    is( $user->weekly_requests_limit(),        $weekly_requests_limit );
    is( $user->weekly_requested_items_limit(), $weekly_requested_items_limit );
    ok( $user->active() );
    ok( $user->global_api_key() );
    ok( $user->password_hash() );
    ok( $user->has_role( 'admin' ) );
}

sub test_all_users($)
{
    my ( $db ) = @_;

    my $email                        = 'test@user.info';
    my $full_name                    = 'Test user info';
    my $notes                        = 'Test test test';
    my $weekly_requests_limit        = 123;
    my $weekly_requested_items_limit = 456;

    eval {

        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                        => $email,
            full_name                    => $full_name,
            notes                        => $notes,
            role_ids                     => [ 1 ],
            active                       => 1,
            password                     => 'userinfo',
            password_repeat              => 'userinfo',
            activation_url               => '',                              # user is active, no need for activation URL
            weekly_requests_limit        => $weekly_requests_limit,
            weekly_requested_items_limit => $weekly_requested_items_limit,
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    my $all_users = MediaWords::DBI::Auth::Profile::all_users( $db );
    is( scalar( @{ $all_users } ), 1 );

    my $user = $all_users->[ 0 ];

    is( $user->email(),                        $email );
    is( $user->full_name(),                    $full_name );
    is( $user->notes(),                        $notes );
    is( $user->weekly_requests_limit(),        $weekly_requests_limit );
    is( $user->weekly_requested_items_limit(), $weekly_requested_items_limit );
    ok( $user->active() );
    ok( $user->global_api_key() );
    ok( $user->password_hash() );
    ok( $user->has_role( 'admin' ) );
}

sub main
{
    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;
            test_user_info( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my $db = shift;
            test_all_users( $db );
        }
    );
}

main();
