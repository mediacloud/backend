package MediaWords::DBI::Auth::Profile;

#
# User profile helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::DBI::Auth::Password;
use MediaWords::DBI::Auth::User::ExistingUser;

# Fetch a hash of basic user information (email, full name, notes, non-IP
# limited API key)
#
# Fetches both active and deactivated users; checking whether or not the user
# is active is left to the controller.
#
# die()s on error
sub user_info($$)
{
    my ( $db, $email ) = @_;

    unless ( $email )
    {
        LOGCONFESS "User email is not defined.";
    }

    # Fetch readonly information about the user
    my $userinfo;
    eval {
        $userinfo = $db->query(
            <<"SQL",
            SELECT auth_users.auth_users_id,
                   auth_users.email,
                   auth_users.password_hash,
                   auth_users.full_name,
                   auth_users.notes,
                   auth_users.active,
                   auth_user_api_keys.api_key,
                   auth_user_api_keys.ip_address,
                   weekly_requests_sum,
                   weekly_requested_items_sum,
                   auth_user_limits.weekly_requests_limit,
                   auth_user_limits.weekly_requested_items_limit,
                   ARRAY_TO_STRING(ARRAY_AGG(auth_roles.role), ' ') AS roles

            FROM auth_users
                INNER JOIN auth_user_api_keys
                    ON auth_users.auth_users_id = auth_user_api_keys.auth_users_id
                INNER JOIN auth_user_limits
                    ON auth_users.auth_users_id = auth_user_limits.auth_users_id
                LEFT JOIN auth_users_roles_map
                    ON auth_users.auth_users_id = auth_users_roles_map.auth_users_id
                LEFT JOIN auth_roles
                    ON auth_users_roles_map.auth_roles_id = auth_roles.auth_roles_id,
                auth_user_limits_weekly_usage( \$1 )

            WHERE auth_users.email = \$1

              -- Return only non-IP limited API key
              AND auth_user_api_keys.ip_address IS NULL

            GROUP BY auth_users.auth_users_id,
                   auth_users.email,
                   auth_users.password_hash,
                   auth_users.full_name,
                   auth_users.notes,
                   auth_users.active,
                   auth_user_api_keys.api_key,
                   auth_user_api_keys.ip_address,
                   weekly_requests_sum,
                   weekly_requested_items_sum,
                   auth_user_limits.weekly_requests_limit,
                   auth_user_limits.weekly_requested_items_limit

            LIMIT 1
SQL
            $email
        )->hash;
    };
    if ( $@ or ( !$userinfo ) )
    {
        LOGCONFESS "Unable to fetch user with email '$email': $@";
    }

    unless ( ref( $userinfo ) eq ref( {} ) and $userinfo->{ auth_users_id } )
    {
        LOGCONFESS "User with email '$email' was not found.";
    }

    # Make an array out of list of roles
    $userinfo->{ roles } = [ split( ' ', $userinfo->{ roles } ) ];

    return $userinfo;
}

# Fetch and return a list of users and their roles; returns an arrayref
sub all_users($)
{
    my ( $db ) = @_;

    # List a full list of roles near each user because (presumably) one can then find out
    # whether or not a particular user has a specific role faster.
    my $users = $db->query(
        <<"SQL"
        SELECT
            auth_users.auth_users_id,
            auth_users.email,
            auth_users.full_name,
            auth_users.notes,
            auth_users.active,

            -- Role from a list of all roles
            all_user_roles.role,

            -- Boolean denoting whether the user has that particular role
            ARRAY(
                SELECT r_auth_roles.role
                FROM auth_users AS r_auth_users
                    INNER JOIN auth_users_roles_map AS r_auth_users_roles_map
                        ON r_auth_users.auth_users_id = r_auth_users_roles_map.auth_users_id
                    INNER JOIN auth_roles AS r_auth_roles
                        ON r_auth_users_roles_map.auth_roles_id = r_auth_roles.auth_roles_id
                WHERE auth_users.auth_users_id = r_auth_users.auth_users_id
            ) @> ARRAY[all_user_roles.role] AS user_has_that_role

        FROM auth_users,
             (SELECT role FROM auth_roles ORDER BY auth_roles_id) AS all_user_roles

        ORDER BY auth_users.auth_users_id
SQL
    )->hashes;

    my $unique_users = {};

    # Make a hash of unique users and their rules
    for my $user ( @{ $users } )
    {
        my $auth_users_id = $user->{ auth_users_id } + 0;
        $unique_users->{ $auth_users_id }->{ 'auth_users_id' } = $auth_users_id;
        $unique_users->{ $auth_users_id }->{ 'email' }         = $user->{ email };
        $unique_users->{ $auth_users_id }->{ 'full_name' }     = $user->{ full_name };
        $unique_users->{ $auth_users_id }->{ 'notes' }         = $user->{ notes };
        $unique_users->{ $auth_users_id }->{ 'active' }        = $user->{ active };

        if ( !ref( $unique_users->{ $auth_users_id }->{ 'roles' } ) eq ref( {} ) )
        {
            $unique_users->{ $auth_users_id }->{ 'roles' } = {};
        }

        $unique_users->{ $auth_users_id }->{ 'roles' }->{ $user->{ role } } = $user->{ user_has_that_role };
    }

    $users = [];
    foreach my $auth_users_id ( sort { $a <=> $b } keys %{ $unique_users } )
    {
        push( @{ $users }, $unique_users->{ $auth_users_id } );
    }

    return $users;
}

# Update an existing user; die() on error
# Undefined user fields won't be set.
sub update_user($$)
{
    my ( $db, $existing_user ) = @_;

    unless ( $existing_user )
    {
        die "Existing user is undefined.";
    }
    unless ( ref( $existing_user ) eq 'MediaWords::DBI::Auth::User::ExistingUser' )
    {
        die "Existing user is not MediaWords::DBI::Auth::User::ExistingUser.";
    }

    TRACE "Modifying user: " . MediaWords::Util::Log::dump_terse( $existing_user );

    # Check if user exists
    my $userinfo;
    eval { $userinfo = user_info( $db, $existing_user->email() ); };
    if ( $@ or ( !$userinfo ) )
    {
        die 'User with email address "' . $existing_user->email() . '" does not exist.';
    }

    # Begin transaction
    $db->begin_work;

    if ( defined( $existing_user->full_name() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_users
            SET full_name = ?
            WHERE email = ?
SQL
            $existing_user->full_name(), $existing_user->email()
        );
    }

    if ( defined( $existing_user->notes() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_users
            SET notes = ?
            WHERE email = ?
SQL
            $existing_user->notes(), $existing_user->email()
        );
    }

    if ( defined( $existing_user->active() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_users
            SET active = ?
            WHERE email = ?
SQL
            normalize_boolean_for_db( $existing_user->active() ), $existing_user->email()
        );
    }

    if ( defined $existing_user->password() )
    {
        eval {
            Readonly my $do_not_inform_via_email => 1;
            MediaWords::DBI::Auth::ChangePassword::change_password(
                $db,
                $existing_user->email(),
                $existing_user->password(),
                $existing_user->password_repeat(),
                $do_not_inform_via_email
            );
        };
        if ( $@ )
        {
            my $error_message = "Unable to change password: $@";

            $db->rollback;
            die $error_message;
        }
    }

    if ( defined( $existing_user->weekly_requests_limit() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requests_limit = ?
            WHERE auth_users_id = ?
SQL
            $existing_user->weekly_requests_limit(), $userinfo->{ auth_users_id }
        );
    }

    if ( defined( $existing_user->weekly_requested_items_limit() ) )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requested_items_limit = ?
            WHERE auth_users_id = ?
SQL
            $existing_user->weekly_requested_items_limit(), $userinfo->{ auth_users_id }
        );
    }

    if ( defined( $existing_user->role_ids() ) )
    {

        $db->query(
            <<SQL,
            DELETE FROM auth_users_roles_map
            WHERE auth_users_id = ?
SQL
            $userinfo->{ auth_users_id }
        );
        for my $auth_roles_id ( @{ $existing_user->role_ids() } )
        {
            $db->query(
                <<SQL,
                INSERT INTO auth_users_roles_map (auth_users_id, auth_roles_id) VALUES (?, ?)
SQL
                $userinfo->{ auth_users_id }, $auth_roles_id
            );
        }
    }

    # End transaction
    $db->commit;
}

# Delete user; die()s on error
sub delete_user($$)
{
    my ( $db, $email ) = @_;

    # Check if user exists
    my $userinfo;
    eval { $userinfo = user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "User with email address '$email' does not exist.";
    }

    # Delete the user (PostgreSQL's relation will take care of 'auth_users_roles_map')
    $db->query(
        <<SQL,
        DELETE FROM auth_users
        WHERE email = ?
SQL
        $email
    );
}

1;
