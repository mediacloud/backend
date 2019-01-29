package MediaWords::Util::Config::Common;

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

{
    package MediaWords::Util::Config::Common::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use MediaWords::Util::Python;

    MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.config.common' );

    1;
}

sub database()
{
    return MediaWords::Util::Config::Common::PythonProxy::CommonConfig::database();
}

sub amazon_s3_downloads()
{
    return MediaWords::Util::Config::Common::PythonProxy::CommonConfig::amazon_s3_downloads();
}

sub rabbitmq()
{
    return MediaWords::Util::Config::Common::PythonProxy::CommonConfig::rabbitmq();
}

sub smtp()
{
    return MediaWords::Util::Config::Common::PythonProxy::CommonConfig::smtp();
}

sub download_storage()
{
    return MediaWords::Util::Config::Common::PythonProxy::CommonConfig::download_storage();
}

sub user_agent()
{
    return MediaWords::Util::Config::Common::PythonProxy::CommonConfig::user_agent();
}

sub email_from_address()
{
    return MediaWords::Util::Config::Common::PythonProxy::CommonConfig::email_from_address();
}

sub solr_url()
{
    return MediaWords::Util::Config::Common::PythonProxy::CommonConfig::solr_url();
}

1;
