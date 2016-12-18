package MediaWords::Util::Config;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

BEGIN {

    use File::Basename;
    use File::Spec;
    use Cwd qw( realpath );
    use File::Spec;

    sub get_mc_python_dir()
    {
        return realpath(File::Spec->canonpath(dirname( __FILE__ ) . "/../../../" . 'mediacloud/'));
    }

    # ::CommonLibs doesn't set PYTHONPATH
    $ENV{ PYTHONPATH } = get_mc_python_dir();
}

# Can't use get_mc_python_dir() ourselves
use Inline Python => get_mc_python_dir() . '/mediawords/util/config.py';

1;
