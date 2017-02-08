package MediaWords::Util;    # not ::Pages to be able to load "Pages" Python class from pages.py

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.util.pages' );

1;
