package MediaWords::DBI::Stories::Process;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.stories.process' );

1;
