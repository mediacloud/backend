package MediaWords::Util::Config::Facebook;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

{
    package MediaWords::Util::Config::Facebook::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use MediaWords::Util::Python;

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.config.facebook' );

    1;
}

sub is_enabled()
{
    return MediaWords::Util::Config::Facebook::PythonProxy::FacebookConfig::is_enabled();
}

sub app_id()
{
    return MediaWords::Util::Config::Facebook::PythonProxy::FacebookConfig::app_id();
}

sub app_secret()
{
    return MediaWords::Util::Config::Facebook::PythonProxy::FacebookConfig::app_secret();
}

sub timeout()
{
    return MediaWords::Util::Config::Facebook::PythonProxy::FacebookConfig::timeout();
}

1;
