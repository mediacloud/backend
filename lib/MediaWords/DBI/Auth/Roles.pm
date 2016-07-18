package MediaWords::DBI::Auth::Roles;

#
# Authentication roles (keep in sync with "auth_roles" table)
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

# Do everything, including editing users
Readonly our $ADMIN => 'admin';

# Read-only access to admin interface
Readonly our $ADMIN_READONLY => 'admin-readonly';

# Add / edit media; includes feeds
Readonly our $MEDIA_EDIT => 'media-edit';

# Add / edit stories
Readonly our $STORIES_EDIT => 'stories-edit';

# Topic mapper; includes media and story editing
Readonly our $TM => 'tm';

# topic mapper; excludes media and story editing
Readonly our $TM_READONLY => 'tm-readonly';

# Access to the stories API
Readonly our $STORIES_API => 'stories-api';

# Access to the /search pages
Readonly our $SEARCH => 'search';

1;
