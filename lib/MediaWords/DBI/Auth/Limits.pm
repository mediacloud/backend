package MediaWords::DBI::Auth::Limits;

#
# Authentication helpers related to user request limits
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::Roles;

# Get default weekly request limit
sub default_weekly_requests_limit($)
{
    my $db = shift;

    my $default_weekly_requests_limit = $db->query(
        <<SQL
        SELECT column_default AS default_weekly_requests_limit
        FROM information_schema.columns
        WHERE (table_schema, table_name) = ('public', 'auth_user_limits')
          AND column_name = 'weekly_requests_limit'
SQL
    )->hash;
    unless ( ref( $default_weekly_requests_limit ) eq ref( {} )
        and defined( $default_weekly_requests_limit->{ default_weekly_requests_limit } ) )
    {
        die "Unable to fetch default weekly requests limit.";
    }

    return $default_weekly_requests_limit->{ default_weekly_requests_limit } + 0;
}

# Get default weekly requested items limit
sub default_weekly_requested_items_limit($)
{
    my $db = shift;

    my $default_weekly_requested_items_limit = $db->query(
        <<SQL
        SELECT column_default AS default_weekly_requested_items_limit
        FROM information_schema.columns
        WHERE (table_schema, table_name) = ('public', 'auth_user_limits')
          AND column_name = 'weekly_requested_items_limit'
SQL
    )->hash;
    unless ( ref( $default_weekly_requested_items_limit ) eq ref( {} )
        and defined( $default_weekly_requested_items_limit->{ default_weekly_requested_items_limit } ) )
    {
        die "Unable to fetch default weekly requested items limit.";
    }

    return $default_weekly_requested_items_limit->{ default_weekly_requested_items_limit } + 0;
}

# User roles that are not limited by the weekly requests / requested items limits
sub roles_exempt_from_user_limits()
{
    return [
        $MediaWords::DBI::Auth::Roles::List::ADMIN,             #
        $MediaWords::DBI::Auth::Roles::List::ADMIN_READONLY,    #
    ];
}

1;
