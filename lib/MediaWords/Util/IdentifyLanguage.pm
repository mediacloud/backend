package MediaWords::Util::IdentifyLanguage;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.identify_language' );

1;
