package MediaWords::DBI::Stories::Process;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'extract_and_vector.dbi.stories.process' );

1;
