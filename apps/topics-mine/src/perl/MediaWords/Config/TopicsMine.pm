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

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'topics_mine.config' );

    1;
}

sub _python_config()
{
    return MediaWords::Util::Config::TopicsMine::PythonProxy::TopicsMineConfig->new();
}

1;
