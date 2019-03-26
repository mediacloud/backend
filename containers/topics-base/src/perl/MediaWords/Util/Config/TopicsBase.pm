package MediaWords::Util::Config::TopicsBase;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

{
    package MediaWords::Util::Config::TopicsBase::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use MediaWords::Util::Python;

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.config.topics_base' );

    1;
}

sub topic_alert_emails()
{
    return MediaWords::Util::Config::TopicsBase::PythonProxy::TopicsBaseConfig::topic_alert_emails();
}

1;
