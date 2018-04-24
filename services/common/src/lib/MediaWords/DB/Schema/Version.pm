package MediaWords::DB::Schema::Version;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.db.schema.version' );

1;
