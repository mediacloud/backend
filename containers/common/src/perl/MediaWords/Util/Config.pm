package MediaWords::Util::Config;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

use MediaWords::Util::Python;

BEGIN
{

    use File::Basename;
    use File::Spec;
    use Cwd qw( realpath );
    use File::Spec;

    sub get_mc_python_dir()
    {
        return realpath( File::Spec->canonpath( dirname( __FILE__ ) . "/../../../" . 'mediacloud/' ) );
    }

    # ::CommonLibs doesn't set PYTHONPATH
    $ENV{ PYTHONPATH } = get_mc_python_dir();
}

MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.config' );

1;
