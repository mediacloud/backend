package MediaWords::DB::Schema::Version;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use MediaWords::Util::Config;
use Inline Python => MediaWords::Util::Config::get_mc_python_dir() . '/mediawords/db/schema/version.py';

1;
