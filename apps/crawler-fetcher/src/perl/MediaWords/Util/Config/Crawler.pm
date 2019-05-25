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

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'crawler_fetcher.config' );

    1;
}

sub new($)
{
    my ( $class ) = @_;

    my $self = {};
    bless $self, $class;

    return $self;
}

sub _python_config()
{
    return MediaWords::Util::Config::Crawler::PythonProxy::CrawlerConfig->new();
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
