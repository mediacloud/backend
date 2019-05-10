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

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'facebook_fetch_story_stats.config' );

    1;
}

sub _python_config()
{
    return MediaWords::Util::Config::Facebook::PythonProxy::FacebookConfig->new();
}

sub is_enabled()
{
    return _python_config()->is_enabled();
}

sub app_id()
{
    return _python_config()->app_id();
}

sub app_secret()
{
    return _python_config()->app_secret();
}

sub timeout()
{
    return _python_config()->timeout();
}

1;
