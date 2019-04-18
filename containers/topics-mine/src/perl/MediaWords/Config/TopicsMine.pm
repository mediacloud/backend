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

sub _python_config()
{
    return MediaWords::Util::Config::Common::PythonProxy::TopicsMineConfig->new();
}

sub crimson_hexagon_api_key()
{
    return _python_config()->crimson_hexagon_api_key();
}

1;
