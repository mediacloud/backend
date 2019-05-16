package MediaWords::DBI::Auth::Roles::List;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

import_python_module( __PACKAGE__, 'webapp.auth.roles.list' );

# Inline::Perl doesn't seem to know how to call static methods
my $user_roles = MediaWords::DBI::Auth::Roles::List::UserRoles->new();

# Pointers to Python variables
Readonly our $ADMIN => $user_roles->admin();

Readonly our $ADMIN_READONLY => $user_roles->admin_readonly();

Readonly our $MEDIA_EDIT => $user_roles->media_edit();

Readonly our $STORIES_EDIT => $user_roles->stories_edit();

Readonly our $TM => $user_roles->tm();

Readonly our $TM_READONLY => $user_roles->tm_readonly();

Readonly our $STORIES_API => $user_roles->stories_api();

1;
