#!/usr/bin/env perl
#
# See MediaWords::DB::Schema for definition of which functions to add
#
# Set the MEDIAWORDS_CREATE_DB_DO_NOT_CONFIRM=1 environment variable to create
# the database without confirming the action.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Auth;
use MediaWords::DBI::Auth::Limits;
use MediaWords::Util::CSV;
use MediaWords::Util::Text;

# return true if an auth_users row with the email already exists
sub user_exists
{
    my ( $db, $email ) = @_;

    my $user_exists = $db->query( "select 1 from auth_users where email = ?", $email )->hash;

    return $user_exists ? 1 : 0;
}

# create a new user
sub create_user
{
    my ( $db, $email, $full_name, $notes, $mc_url ) = @_;

    if ( user_exists( $db, $email ) )
    {
        WARN "User already exists for email: '$email'";
        return;
    }

    my $default_weekly_requests_limit        = MediaWords::DBI::Auth::Limits::default_weekly_requests_limit( $db );
    my $default_weekly_requested_items_limit = MediaWords::DBI::Auth::Limits::default_weekly_requested_items_limit( $db );

    my $user_password = MediaWords::Util::Text::random_string( 64 );

    # Add user
    eval {

        my $role_ids = MediaWords::DBI::Auth::Roles::default_role_ids( $db );
        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                        => $email,
            full_name                    => $full_name,
            notes                        => $notes,
            role_ids                     => $role_ids,
            active                       => 1,
            password                     => $user_password,
            password_repeat              => $user_password,
            activation_url               => '',                                      # user is active
            weekly_requests_limit        => $default_weekly_requested_items_limit,
            weekly_requested_items_limit => $default_weekly_requested_items_limit,
        );

        INFO "Adding user: " . Dumper( $new_user );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    if ( $@ )
    {
        die "error adding user '$email': $@";
    }

    eval {
        MediaWords::DBI::Auth::ResetPassword::send_password_reset_token(
            $db,                     #
            $email,                  #
            "$mc_url/login/reset"    #
        );
    };
    if ( $@ )
    {
        die "error resetting password '$email': $@";
    }
}

sub main
{
    my ( $mc_url, $file ) = @ARGV;

    die( "$0 < mc url > < csv file >" ) unless ( $mc_url && $file );

    die( "invalid mc url: $mc_url" ) unless ( $mc_url =~ /https?:/i );

    my $users = MediaWords::Util::CSV::get_csv_as_hashes( $file, 1 );

    my $db = MediaWords::DB::connect_to_db;

    for my $user ( @{ $users } )
    {
        next if ( $user->{ registered } eq 'yes' );

        my $notes = ( $user->{ 'company_/_organization' } || '' ) . ' ' . ( $user->{ motivation } || '' );

        create_user( $db, $user->{ email }, $user->{ name }, $notes, $mc_url );
    }
}

main();
