package MediaWords::Util::SQL;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use MediaWords::Util::Config;
use Inline Python => MediaWords::Util::Config::get_mc_python_dir() . '/mediawords/util/sql.py';

1;
