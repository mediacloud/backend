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

sub database()
{
    my $python_config = MediaWords::Util::Config::Common::PythonProxy::CommonConfig::database();
    my $config = MediaWords::Util::Config::Common::Database->new( $python_config );
    return $config;
}

sub amazon_s3_downloads()
{
    my $python_config = MediaWords::Util::Config::Common::PythonProxy::CommonConfig::amazon_s3_downloads();
    my $config = MediaWords::Util::Config::Common::AmazonS3Downloads->new( $python_config );
    return $config;
}

sub rabbitmq()
{
    my $python_config = MediaWords::Util::Config::Common::PythonProxy::CommonConfig::rabbitmq();
    my $config = MediaWords::Util::Config::Common::RabbitMQ->new( $python_config );
    return $config;
}

sub smtp()
{
    my $python_config = MediaWords::Util::Config::Common::PythonProxy::CommonConfig::smtp();
    my $config = MediaWords::Util::Config::Common::SMTP->new( $python_config );
    return $config;
}

sub download_storage()
{
    my $python_config = MediaWords::Util::Config::Common::PythonProxy::CommonConfig::download_storage();
    my $config = MediaWords::Util::Config::Common::DownloadStorage->new( $python_config );
    return $config;
}

sub user_agent()
{
    my $python_config = MediaWords::Util::Config::Common::PythonProxy::CommonConfig::user_agent();
    my $config = MediaWords::Util::Config::Common::UserAgent->new( $python_config );
    return $config;
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
