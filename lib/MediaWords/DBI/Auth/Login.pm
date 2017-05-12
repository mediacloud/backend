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

# Login and get an IP API key for the logged in user.
# Returns API key if login is successful, undef otherwise.
sub login_and_get_ip_api_key_for_user($$$$)
{
    my ( $db, $email, $password, $ip_address ) = @_;

    unless ( $email and $password )
    {
        die "Email and password must be defined";
    }

    unless ( $ip_address )
    {
        die "Unable to find IP address for request";
    }

    my $user;
    eval { $user = MediaWords::DBI::Auth::Profile::user_auth( $db, $email ); };
    if ( $@ or ( !$user ) )
    {
        die "Unable to find authentication roles for email '$email'";
    }

    unless ( $user->{ active } )
    {
        die "User with email '$email' is not active.";
    }

    unless ( MediaWords::DBI::Auth::Password::password_hash_is_valid( $user->{ password_hash }, $password ) )
    {
        die "Password for user '$email' is invalid.";
    }

    my $auth_user_ip_api_key = $db->query(
        <<SQL,
        SELECT *
        FROM auth_user_api_keys
        WHERE auth_users_id = \$1
          AND ip_address = \$2
SQL
        $user->{ auth_users_id }, $ip_address
    )->hash;

    my $auit_hash = { auth_users_id => $user->{ auth_users_id }, ip_address => $ip_address };
    $auth_user_ip_api_key //= $db->create( 'auth_user_api_keys', $auit_hash );

    return $auth_user_ip_api_key->{ api_key };
}

# Post-successful login database tasks
sub post_successful_login($$)
{
    my ( $db, $email ) = @_;

    # Reset the password reset token (if any)
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = ?
SQL
        $email
    );
}

# Post-unsuccessful login database tasks
sub post_unsuccessful_login($$)
{
    my ( $db, $email ) = @_;

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
}

# Check if user is trying to log in too soon after last unsuccessful attempt to do that
# Returns 1 if too soon, 0 otherwise
sub user_is_trying_to_login_too_soon($$)
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

1;
