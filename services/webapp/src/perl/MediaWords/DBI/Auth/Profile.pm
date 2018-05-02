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
use MediaWords::DBI::Auth::User::ModifyUser;
use MediaWords::Util::Mail;

# Fetch user information (email, full name, notes, API keys, password hash)
#
# Returns ::CurrentUser object or die()s on error.
#
# Fetches both active and deactivated users; checking whether or not the user
# is active is left to the controller.
sub user_info($$)
{
    my ( $db, $email ) = @_;

    unless ( $email )
    {
        LOGCONFESS "User email is not defined.";
    }

    # Fetch readonly information about the user
    my $user_info;
    eval {
        $user_info = $db->query(
            <<"SQL",
            SELECT auth_users.auth_users_id,
                   auth_users.email,
                   auth_users.full_name,
                   auth_users.notes,
                   EXTRACT(epoch FROM NOW())::bigint AS created_timestamp,
                   auth_users.active,
                   auth_users.password_hash,
                   auth_user_api_keys.api_key,
                   auth_user_api_keys.ip_address,
                   weekly_requests_sum,
                   weekly_requested_items_sum,
                   auth_user_limits.weekly_requests_limit,
                   auth_user_limits.weekly_requested_items_limit,
                   auth_roles.auth_roles_id,
                   auth_roles.role

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
SQL
            $email
        )->hashes;
    };
    if ( $@ or ( !$user_info ) )
    {
        LOGCONFESS "Unable to fetch user with email '$email': $@";
    }

    unless ( ref( $user_info ) eq ref( [] ) and $user_info->[ 0 ] and $user_info->[ 0 ]->{ auth_users_id } )
    {
        LOGCONFESS "User with email '$email' was not found.";
    }

    my $unique_api_keys = {};
    my $unique_roles    = {};

    foreach my $row ( @{ $user_info } )
    {

        # Should have at least one API key
        $unique_api_keys->{ $row->{ api_key } } = $row->{ ip_address };

        # Might have some roles
        if ( defined $row->{ auth_roles_id } )
        {
            $unique_roles->{ $row->{ auth_roles_id } } = $row->{ role };
        }
    }

    my $api_keys = [];
    my $roles    = [];
    foreach my $api_key ( sort( keys %{ $unique_api_keys } ) )
    {
        push(
            @{ $api_keys },
            MediaWords::DBI::Auth::User::CurrentUser::APIKey->new(
                api_key    => $api_key,
                ip_address => $unique_api_keys->{ $api_key },
            )
        );
    }
    foreach my $role_id ( sort( keys %{ $unique_roles } ) )
    {
        push(
            @{ $roles },
            MediaWords::DBI::Auth::User::CurrentUser::Role->new(
                id   => $role_id,
                role => $unique_roles->{ $role_id },
            )
        );
    }

    my $first_row = $user_info->[ 0 ];

    my $user = MediaWords::DBI::Auth::User::CurrentUser->new(
        id                           => $first_row->{ auth_users_id },
        email                        => $email,
        full_name                    => $first_row->{ full_name },
        notes                        => $first_row->{ notes },
        created_timestamp            => $first_row->{ created_timestamp },
        active                       => $first_row->{ active } + 0,
        password_hash                => $first_row->{ password_hash },
        roles                        => $roles,
        api_keys                     => $api_keys,
        weekly_requests_limit        => $first_row->{ weekly_requests_limit },
        weekly_requested_items_limit => $first_row->{ weekly_requested_items_limit },
        weekly_requests_sum          => $first_row->{ weekly_requests_sum },
        weekly_requested_items_sum   => $first_row->{ weekly_requested_items_sum },
    );

    return $user;
}

# Fetch and return a list of users and their roles; returns an arrayref
sub all_users($)
{
    my ( $db ) = @_;

    # Start a transaction so that the list of users doesn't change while we run
    # separate queries with user_info()
    $db->begin;

    my $user_emails = $db->query(
        <<"SQL"
            SELECT email
            FROM auth_users
            ORDER BY auth_users_id
SQL
    )->flat;

    my $users = [];

    foreach my $email ( @{ $user_emails } )
    {
        my $user = user_info( $db, $email );
        push( @{ $users }, $user );
    }

    $db->commit;

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
    unless ( ref( $existing_user ) eq 'MediaWords::DBI::Auth::User::ModifyUser' )
    {
        die "Existing user is not MediaWords::DBI::Auth::User::ModifyUser.";
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
            $existing_user->weekly_requests_limit(), $userinfo->id()
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
            $existing_user->weekly_requested_items_limit(), $userinfo->id()
        );
    }

    if ( defined( $existing_user->role_ids() ) )
    {

        $db->query(
            <<SQL,
            DELETE FROM auth_users_roles_map
            WHERE auth_users_id = ?
SQL
            $userinfo->id()
        );
        for my $auth_roles_id ( @{ $existing_user->role_ids() } )
        {
            $db->query(
                <<SQL,
                INSERT INTO auth_users_roles_map (auth_users_id, auth_roles_id) VALUES (?, ?)
SQL
                $userinfo->id(), $auth_roles_id
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
    eval { $userinfo = user_info( $db, $email ); };
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

    eval {

        my $message = MediaWords::Util::Mail::Message::Templates::AuthAPIKeyResetMessage->new(
            {
                to        => $email,
                full_name => $userinfo->full_name(),
            }
        );
        unless ( MediaWords::Util::Mail::send_email( $message ) )
        {
            die "Unable to send email message.";
        }

    };
    if ( $@ )
    {
        $db->rollback;
        WARN "Unable to send email about reset API key: $@";
        die "Unable to send email about reset API key.";
    }

    $db->commit;
}

1;
