package MediaWords::Util::Config::TopicsFetchTwitterURLs;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

{
    package MediaWords::Util::Config::TopicsFetchTwitterURLs::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use MediaWords::Util::Python;

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.config.topics_fetch_twitter_urls' );

    1;
}

sub twitter_consumer_key()
{
    return MediaWords::Util::Config::TopicsFetchTwitterURLs::PythonProxy::TopicsFetchTwitterURLsConfig::twitter_consumer_key();
}

sub twitter_consumer_secret()
{
    return MediaWords::Util::Config::TopicsFetchTwitterURLs::PythonProxy::TopicsFetchTwitterURLsConfig::twitter_consumer_secret();
}

sub twitter_access_token()
{
    return MediaWords::Util::Config::TopicsFetchTwitterURLs::PythonProxy::TopicsFetchTwitterURLsConfig::twitter_access_token();
}

sub twitter_access_token_secret()
{
    return MediaWords::Util::Config::TopicsFetchTwitterURLs::PythonProxy::TopicsFetchTwitterURLsConfig::twitter_access_token_secret();
}

1;
