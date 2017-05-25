package MediaWords::DBI::Auth::Login;

#
# User login helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::DBI::Auth::Profile;

# Post-unsuccessful login delay (in seconds)
Readonly my $POST_UNSUCCESSFUL_LOGIN_DELAY => 1;

# Check if user is trying to log in too soon after last unsuccessful attempt to do that
# Returns 1 if too soon, 0 otherwise
sub _user_is_trying_to_login_too_soon($$)
{
    my ( $db, $email ) = @_;

    my $interval = "$POST_UNSUCCESSFUL_LOGIN_DELAY seconds";

    my $user = $db->query(
        <<"SQL",
        SELECT auth_users_id,
               email
        FROM auth_users
        WHERE email = ?
              AND last_unsuccessful_login_attempt >= LOCALTIMESTAMP - INTERVAL '$interval'
        ORDER BY auth_users_id
        LIMIT 1
SQL
        $email
    )->hash;

    if ( ref( $user ) eq ref( {} ) and $user->{ auth_users_id } )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Log in with username and password
# Return ExistingUser object if login is successful, die() otherwise
sub login_with_email_password($$$)
{
    my ( $db, $email, $password ) = @_;

    my $user;

    eval {

        unless ( $email and $password )
        {
            die "Email and password must be defined";
        }

        eval { $user = MediaWords::DBI::Auth::Profile::user_info( $db, $email ); };
        if ( $@ or ( !$user ) )
        {
            die "Unable to find user with email '$email'";
        }

        # Check if user has tried to log in unsuccessfully before and now is trying
        # again too fast
        if ( _user_is_trying_to_login_too_soon( $db, $email ) )
        {
            die "User '$email' is trying to log in too soon after the last unsuccessful attempt.";
        }

        unless ( $user->active() )
        {
            die "User with email '$email' is not active.";
        }

        unless ( MediaWords::DBI::Auth::Password::password_hash_is_valid( $user->password_hash(), $password ) )
        {
            die "Password for user '$email' is invalid.";
        }

        # Reset password reset token (if any)
        $db->query(
            <<"SQL",
            UPDATE auth_users
            SET password_reset_token_hash = NULL
            WHERE email = ?
SQL
            $email
        );

    };
    if ( $@ or ( !$user ) )
    {

        INFO "Login failed for $email, will delay any successive login attempt for $POST_UNSUCCESSFUL_LOGIN_DELAY seconds.";

        # Set the unsuccessful login timestamp
        # (TIMESTAMP 'now' returns "current transaction's start time", so using LOCALTIMESTAMP instead)
        $db->query(
            <<"SQL",
            UPDATE auth_users
            SET last_unsuccessful_login_attempt = LOCALTIMESTAMP
            WHERE email = ?
SQL
            $email
        );

        # It might make sense to sleep() here for the duration of $POST_UNSUCCESSFUL_LOGIN_DELAY seconds
        # to prevent legitimate users from trying to log in too fast.
        # However, when being actually brute-forced through multiple HTTP connections, this approach might
        # end up creating a lot of processes that would sleep() and take up memory.
        # So, let's return the error page ASAP and hope that a legitimate user won't be able to reenter
        # his / her password before the $POST_UNSUCCESSFUL_LOGIN_DELAY amount of seconds pass.

        # Don't give out a specific reason for the user to not be able to find
        # out which user emails are registered
        die "Login for user '$email' has failed.";
    }

    return $user;
}

# Login and get an IP API key for the logged in user.
# Returns API key if login is successful, die() otherwise
sub login_with_email_password_get_ip_api_key($$$$)
{
    my ( $db, $email, $password, $ip_address ) = @_;

    unless ( $ip_address )
    {
        die "Unable to find IP address for request";
    }

    my $user;
    eval { $user = login_with_email_password( $db, $email, $password ); };
    if ( $@ or ( !$user ) )
    {
        die "Unable to log user '$email' in with provided credentials: $@";
    }

    my $api_key_for_ip_address = $user->api_key_for_ip_address( $ip_address );

    unless ( $api_key_for_ip_address )
    {
        $db->create(
            'auth_user_api_keys',
            {
                auth_users_id => $user->id(),    #
                ip_address    => $ip_address,    #
            }
        );

        # Fetch user again
        $user = login_with_email_password( $db, $email, $password );
        $api_key_for_ip_address = $user->api_key_for_ip_address( $ip_address );

        unless ( $api_key_for_ip_address )
        {
            die "Unable to create per-IP API key for IP address $ip_address.";
        }
    }

    return $api_key_for_ip_address;
}

1;
