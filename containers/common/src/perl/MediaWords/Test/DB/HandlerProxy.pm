package MediaWords::Test::DB::HandlerProxy;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.test.db.handler_proxy' );

1;
