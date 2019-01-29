package MediaWords::Util::Config::TopicsMine;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

{
    package MediaWords::Util::Config::TopicsMine::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use MediaWords::Util::Python;

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.config.topics_mine' );

    1;
}

sub twitter_consumer_key()
{
    return MediaWords::Util::Config::TopicsMine::PythonProxy::TopicsMineConfig::twitter_consumer_key();
}

sub twitter_consumer_secret()
{
    return MediaWords::Util::Config::TopicsMine::PythonProxy::TopicsMineConfig::twitter_consumer_secret();
}

sub twitter_access_token()
{
    return MediaWords::Util::Config::TopicsMine::PythonProxy::TopicsMineConfig::twitter_access_token();
}

sub twitter_access_token_secret()
{
    return MediaWords::Util::Config::TopicsMine::PythonProxy::TopicsMineConfig::twitter_access_token_secret();
}

sub crimson_hexagon_api_key()
{
    return MediaWords::Util::Config::TopicsMine::PythonProxy::TopicsMineConfig::crimson_hexagon_api_key();
}

sub topic_alert_emails()
{
    return MediaWords::Util::Config::TopicsMine::PythonProxy::TopicsMineConfig::topic_alert_emails();
}

1;
