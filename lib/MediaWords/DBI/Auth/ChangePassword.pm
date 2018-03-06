package MediaWords::DBI::Auth::ChangePassword;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.auth.change_password' );

1;
