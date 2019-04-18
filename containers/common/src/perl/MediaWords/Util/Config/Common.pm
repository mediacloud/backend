package MediaWords::Util::Config::Common;

use strict;
use warnings;

use Modern::Perl "2015";

use MediaWords::Util::Config::Common::AmazonS3Downloads;
use MediaWords::Util::Config::Common::Database;
use MediaWords::Util::Config::Common::DownloadStorage;
use MediaWords::Util::Config::Common::RabbitMQ;
use MediaWords::Util::Config::Common::SMTP;
use MediaWords::Util::Config::Common::UserAgent;

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

sub _python_config()
{
    return MediaWords::Util::Config::Common::PythonProxy::CommonConfig->new();
}

sub database()
{
    return MediaWords::Util::Config::Common::Database->new( _python_config()->database() );
}

sub amazon_s3_downloads()
{
    return MediaWords::Util::Config::Common::AmazonS3Downloads->new( _python_config()->amazon_s3_downloads() );
}

sub rabbitmq()
{
    return MediaWords::Util::Config::Common::RabbitMQ->new( _python_config()->rabbitmq() );
}

sub smtp()
{
    return MediaWords::Util::Config::Common::SMTP->new( _python_config()->smtp() );
}

sub download_storage()
{
    return MediaWords::Util::Config::Common::DownloadStorage->new( _python_config()->download_storage() );
}

sub user_agent()
{
    return MediaWords::Util::Config::Common::UserAgent->new( _python_config()->user_agent() );
}

sub email_from_address()
{
    return _python_config()->email_from_address();
}

sub solr_url()
{
    return _python_config()->solr_url();
}

1;
