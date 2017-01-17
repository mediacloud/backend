package MediaWords::DB;    # not ::(Database)Handler to be able to load
                           # "Databasehandler" Python class from handler.py

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use MediaWords::Util::Config;
use Inline Python => MediaWords::Util::Config::get_mc_python_dir() . '/mediawords/db/handler.py';

1;
