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

sub crawler_fetcher_forks()
{
    return MediaWords::Util::Config::Crawler::PythonProxy::CrawlerConfig::crawler_fetcher_forks();
}

sub univision_client_id()
{
    return MediaWords::Util::Config::Crawler::PythonProxy::CrawlerConfig::univision_client_id();
}

sub univision_client_secret()
{
    return MediaWords::Util::Config::Crawler::PythonProxy::CrawlerConfig::univision_client_secret();
}

1;
