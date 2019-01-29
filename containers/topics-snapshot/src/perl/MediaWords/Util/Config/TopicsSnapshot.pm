package MediaWords::Util::Config::TopicsSnapshot;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

{
    package MediaWords::Util::Config::TopicsSnapshot::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use MediaWords::Util::Python;

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.config.topics_snapshot' );

    1;
}

sub model_reps()
{
    return MediaWords::Util::Config::TopicsSnapshot::PythonProxy::TopicsSnapshotConfig::model_reps();
}

1;
