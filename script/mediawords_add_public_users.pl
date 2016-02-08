#!/usr/bin/env perl
#
# See MediaWords::Pg::Schema for definition of which functions to add
#
# Set the MEDIAWORDS_CREATE_DB_DO_NOT_CONFIRM=1 environment variable to create
# the database without confirming the action.
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Auth;
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
        say STDERR "user already exists for email: '$email'";
        return;
    }

    my $default_roles_ids = $db->query( "select auth_roles_id from auth_roles where role in ( 'search' ) " )->flat;
    my $default_weekly_requests_limit          = MediaWords::DBI::Auth::default_weekly_requests_limit( $db ),
      my $default_weekly_requested_items_limit = MediaWords::DBI::Auth::default_weekly_requested_items_limit( $db ),

      my $user_email = $email;
    my $user_full_name                    = $full_name;
    my $user_notes                        = $notes;
    my $user_is_active                    = 1;
    my $user_roles                        = $default_roles_ids;
    my $user_non_public_api_access        = 0;
    my $user_weekly_requests_limit        = $default_weekly_requests_limit;
    my $user_weekly_requested_items_limit = $default_weekly_requested_items_limit;
    my $user_password                     = MediaWords::Util::Text::random_string( 64 );
    my $user_password_repeat              = $user_password;

    say STDERR "adding user: " .
      Dumper( $mc_url, $user_email, $user_full_name, $user_notes, $user_roles, $user_is_active,
        $user_password, $user_password_repeat, $user_non_public_api_access,
        $user_weekly_requests_limit, $user_weekly_requested_items_limit );

    # Add user
    my $add_user_error_message =
      MediaWords::DBI::Auth::add_user_or_return_error_message( $db, $user_email, $user_full_name,
        $user_notes, $user_roles, $user_is_active, $user_password, $user_password_repeat, $user_non_public_api_access,
        $user_weekly_requests_limit, $user_weekly_requested_items_limit );

    if ( $add_user_error_message )
    {
        die( "error adding user '$email': $add_user_error_message" );
    }

    my $reset_password_error_message =
      MediaWords::DBI::Auth::send_password_reset_token_or_return_error_message( $db, $user_email, "$mc_url/login/reset", 1 );
    die( "error resetting password '$user_email': $reset_password_error_message" ) if ( $reset_password_error_message );
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
