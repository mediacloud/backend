package MediaWords::DBI::Auth::Info;

#
# User information helper
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::DBI::Auth::User::CurrentUser;
use MediaWords::DBI::Auth::User::CurrentUser::APIKey;
use MediaWords::DBI::Auth::User::CurrentUser::Role;

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

1;
