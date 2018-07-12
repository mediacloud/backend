package MediaWords::DBI::Auth::Roles;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.auth.roles' );

1;
