package MediaWords::DBI::Auth::Roles;

#
# Authentication role helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::DBI::Auth::Roles::List;

# Fetch a list of available user roles
sub all_user_roles($)
{
    my ( $db ) = @_;

    my $roles = $db->query(
        <<"SQL"
        SELECT auth_roles_id,
               role,
               description
        FROM auth_roles
        ORDER BY auth_roles_id
SQL
    )->hashes;

    return $roles;
}

# Fetch a user role's ID for a role; die()s if no such role was found
sub role_id_for_role($$)
{
    my ( $db, $role ) = @_;

    if ( !$role )
    {
        LOGCONFESS "Role is empty.";
    }

    my $auth_roles_id = $db->query(
        <<"SQL",
        SELECT auth_roles_id
        FROM auth_roles
        WHERE role = ?
        LIMIT 1
SQL
        $role
    )->hash;
    if ( !( ref( $auth_roles_id ) eq ref( {} ) and $auth_roles_id->{ auth_roles_id } ) )
    {
        LOGCONFESS "Role '$role' was not found.";
    }

    return $auth_roles_id->{ auth_roles_id };
}

# List of role IDs to apply to new users
sub default_role_ids($)
{
    my ( $db ) = @_;

    my $default_role_ids = $db->query(
        <<SQL,
        SELECT auth_roles_id
        FROM auth_roles
        WHERE role = ?
SQL
        $MediaWords::DBI::Auth::Roles::List::SEARCH
    )->flat;

    unless ( scalar( @{ $default_role_ids } ) )
    {
        die 'Unable to find default role IDs';
    }

    return $default_role_ids;
}

1;
