package MediaWords::ActionRole::MediaEditAuthenticated;

#
# Action role that requires its actions to authenticate via API key
#

use strict;
use warnings;

use Moose::Role;
with 'MediaWords::ActionRole::RoleAuthenticated';
use namespace::autoclean;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use HTTP::Status qw(:constants);

use MediaWords::DBI::Auth::Roles ( ':all' );

sub _get_auth_roles
{
    return [ $MediaWords::DBI::Auth::Roles::List::ADMIN, $MediaWords::DBI::Auth::Roles::List::MEDIA_EDIT, ];
}

1;
