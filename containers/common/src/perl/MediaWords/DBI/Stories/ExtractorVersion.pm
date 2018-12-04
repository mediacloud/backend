package MediaWords::DBI::Stories::ExtractorVersion;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.stories.extractor_version' );

1;
