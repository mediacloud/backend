package MediaWords::DBI::Auth;

#
# Authentication roles
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

# Create query; includes ability to create clusters, maps, etc. under clusters
Readonly our $QUERY_CREATE => 'query-create';

# Add / edit media; includes feeds
Readonly our $MEDIA_EDIT => 'media-edit';

# Add / edit stories
Readonly our $STORIES_EDIT => 'stories-edit';

# Controversy mapper; includes media and story editing
Readonly our $CM => 'cm';

# Controversy mapper; excludes media and story editing
Readonly our $CM_READONLY => 'cm-readonly';

# Access to the stories API
Readonly our $STORIES_API => 'stories-api';

# Access to the /search pages
Readonly our $SEARCH => 'search';

1;
