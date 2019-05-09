package MediaWords::DBI::Downloads::Extract;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'extract_and_vector.dbi.downloads.extract' );

1;
