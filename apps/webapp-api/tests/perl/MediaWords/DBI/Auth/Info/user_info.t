use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::DBI::Auth::Info;
use MediaWords::DBI::Auth::Register;
use MediaWords::DBI::Auth::User::Resources;
use MediaWords::Util::Mail;

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
            resource_limits              => MediaWords::DBI::Auth::User::Resources->new(
                weekly_requests          => $weekly_requests_limit,
                weekly_requested_items   => $weekly_requested_items_limit,
            ),
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    ok( !$@, "Unable to add user: $@" );

    my $user = MediaWords::DBI::Auth::Info::user_info( $db, $email );

    ok( $user->user_id() );
    is( $user->email(),                        $email );
    is( $user->full_name(),                    $full_name );
    is( $user->notes(),                        $notes );
    ok( $user->resource_limits() );
    is( $user->resource_limits()->weekly_requests(),        $weekly_requests_limit );
    is( $user->resource_limits()->weekly_requested_items(), $weekly_requested_items_limit );
    ok( $user->active() );
    ok( $user->global_api_key() );
    ok( $user->password_hash() );
    ok( $user->has_role( 'admin' ) );
}

sub main
{
    # Don't actually send any emails
    MediaWords::Util::Mail::enable_test_mode();

    my $db = MediaWords::DB::connect_to_db();

    test_user_info( $db );

    done_testing();
}

main();
