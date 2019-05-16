package MediaWords::DBI::Auth::ResetPassword;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'webapp.auth.reset_password' );

1;
