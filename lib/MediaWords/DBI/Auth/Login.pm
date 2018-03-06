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
sub login_with_email_password($$$;$)
{
    my ( $db, $email, $password, $ip_address ) = @_;

    unless ( $email and $password )
    {
        die "Email and password must be defined";
    }

    my $user;

    eval {

        eval { $user = MediaWords::DBI::Auth::Info::user_info( $db, $email ); };
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

        unless ( MediaWords::DBI::Auth::Password::password_hash_is_valid( $user->password_hash(), $password ) )
        {
            die "Password for user '$email' is invalid.";
        }

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
        die "User '$email' was not found or password is incorrect.";
    }

    unless ( $user->active() )
    {
        die "User with email '$email' is not active.";
    }

    # Reset password reset token (if any)
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = ?
          AND password_reset_token_hash IS NOT NULL
SQL
        $email
    );

    if ( $ip_address )
    {

        unless ( $user->api_key_for_ip_address( $ip_address ) )
        {
            $db->create(
                'auth_user_api_keys',
                {
                    auth_users_id => $user->id(),    #
                    ip_address    => $ip_address,    #
                }
            );

            # Fetch user again
            $user = MediaWords::DBI::Auth::Info::user_info( $db, $email );

            unless ( $user->api_key_for_ip_address( $ip_address ) )
            {
                die "Unable to create per-IP API key for IP $ip_address";
            }
        }

    }

    return $user;
}

# Fetch user object for the API key.
# Only active users are fetched.
# die()s on error
sub login_with_api_key($$$)
{
    my ( $db, $api_key, $ip_address ) = @_;

    unless ( $api_key )
    {
        die "API key is undefined.";
    }
    unless ( $ip_address )
    {
        # Even if provided API key is the global one, we want the IP address
        die "IP address is undefined.";
    }

    my $api_key_user = $db->query(
        <<"SQL",
        SELECT auth_users.email
        FROM auth_users
            INNER JOIN auth_user_api_keys
                ON auth_users.auth_users_id = auth_user_api_keys.auth_users_id
        WHERE
            (
                auth_user_api_keys.api_key = \$1 AND
                (
                    auth_user_api_keys.ip_address IS NULL
                    OR
                    auth_user_api_keys.ip_address = \$2
                )
            )

        GROUP BY auth_users.auth_users_id,
                 auth_users.email
        ORDER BY auth_users.auth_users_id
        LIMIT 1
SQL
        $api_key,
        $ip_address
    )->hash;

    unless ( ref( $api_key_user ) eq ref( {} ) and $api_key_user->{ email } )
    {
        die "Unable to find user for API key '$api_key' and IP address '$ip_address'";
    }

    my $email = $api_key_user->{ email };

    # Check if user has tried to log in unsuccessfully before and now is trying
    # again too fast
    if ( _user_is_trying_to_login_too_soon( $db, $email ) )
    {
        die "User '$email' is trying to log in too soon after the last unsuccessful attempt.";
    }

    my $user = MediaWords::DBI::Auth::Info::user_info( $db, $email );
    unless ( $user )
    {
        die "Unable to fetch user '$email' for API key '$api_key'";
    }

    # Reset password reset token (if any)
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = ?
          AND password_reset_token_hash IS NOT NULL
SQL
        $email
    );

    unless ( $user->active() )
    {
        die "User '$email' for API key '$api_key' is not active.";
    }

    return $user;
}

1;
