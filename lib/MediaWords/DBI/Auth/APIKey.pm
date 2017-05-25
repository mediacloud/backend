package MediaWords::DBI::Auth::APIKey;

#
# Authentication helpers related to managing API key(s)
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::Profile;

# API key HTTP GET parameter
Readonly my $API_KEY_PARAMETER => 'key';

# Fetch user object for the API key.
# Only active users are fetched.
# die()s on error
sub user_for_api_key($$$)
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
    my $user = MediaWords::DBI::Auth::Profile::user_info( $db, $email );
    unless ( $user )
    {
        die "Unable to fetch user '$email' for API key '$api_key'";
    }

    unless ( $user->active() )
    {
        die "User '$email' for API key '$api_key' is not active.";
    }

    return $user;
}

# Fetch user object for the API key, using Catalyst's object.
# Only active users are fetched.
# die()s on error
sub user_for_api_key_catalyst($)
{
    my $c = shift;

    my $db         = $c->dbis;
    my $api_key    = $c->request->param( $API_KEY_PARAMETER . '' );
    my $ip_address = $c->request_ip_address();

    return user_for_api_key( $db, $api_key, $ip_address );
}

# Regenerate API key -- creates new non-IP limited API key, removes all
# IP-limited API keys; die()s on error
sub regenerate_api_key($$)
{
    my ( $db, $email ) = @_;

    unless ( $email )
    {
        die 'Email address is empty.';
    }

    # Check if user exists
    my $userinfo;
    eval { $userinfo = MediaWords::DBI::Auth::Profile::user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "User with email address '$email' does not exist.";
    }

    $db->begin;

    # Purge all IP-limited API keys
    $db->query(
        <<SQL,
        DELETE FROM auth_user_api_keys
        WHERE ip_address IS NOT NULL
          AND auth_users_id = (
            SELECT auth_users_id
            FROM auth_users
            WHERE email = ?
          )
SQL
        $email
    );

    # Regenerate non-IP limited API key
    $db->query(
        <<SQL,
        UPDATE auth_user_api_keys

        -- DEFAULT points to a generation function
        SET api_key = DEFAULT

        WHERE ip_address IS NULL
          AND auth_users_id = (
            SELECT auth_users_id
            FROM auth_users
            WHERE email = ?
          )        
SQL
        $email
    );

    $db->commit;
}

1;
