package MediaWords::DBI::Downloads::Store;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.downloads.store' );

1;
