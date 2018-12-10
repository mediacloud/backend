package MediaWords::Util::Config::Common;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

use MediaWords::Util::Python;

MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.config.common' );

1;
