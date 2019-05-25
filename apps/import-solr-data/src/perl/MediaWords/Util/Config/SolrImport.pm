package MediaWords::Util::Config::SolrImport;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

{
    package MediaWords::Util::Config::SolrImport::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use MediaWords::Util::Python;

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'import_solr_data.config' );

    1;
}

sub _python_config()
{
    return MediaWords::Util::Config::SolrImport::PythonProxy::SolrImportConfig->new();
}

sub max_queued_stories()
{
    return _python_config()->max_queued_stories();
}

1;
