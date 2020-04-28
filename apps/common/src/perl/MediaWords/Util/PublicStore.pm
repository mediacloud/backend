package MediaWords::Util::PublicStore;

#
# Store and fetch content from the public s3 store
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.public_store' );

1;
