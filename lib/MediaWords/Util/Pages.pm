package MediaWords::Util;    # not ::Pages to be able to load "Pages" Python class from pages.py

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use MediaWords::Util::Config;
use Inline Python => MediaWords::Util::Config::get_mc_python_dir() . '/mediawords/util/pages.py';

1;
