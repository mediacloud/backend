package MediaWords::Util::Config::Crawler;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

{
    package MediaWords::Util::Config::Crawler::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use MediaWords::Util::Python;

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.config.crawler' );

    1;
}

sub _python_config()
{
    return MediaWords::Util::Config::Common::PythonProxy::CrawlerConfig->new();
}

sub crawler_fetcher_forks()
{
    return _python_config()->crawler_fetcher_forks();
}

sub univision_client_id()
{
    return _python_config()->univision_client_id();
}

sub univision_client_secret()
{
    return _python_config()->univision_client_secret();
}

1;
