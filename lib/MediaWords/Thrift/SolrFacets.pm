package MediaWords::Thrift::SolrFacets;

use strict;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# functions for searching the solr server

use JSON;
use List::Util;

use MediaWords::Languages::Language;
use MediaWords::Util::Config;
use MediaWords::Util::Web;
use List::MoreUtils qw ( uniq );

BEGIN
{

    my $source_root;

    BEGIN
    {
        use FindBin;

        my $base_dir = MediaWords::Util::Config::base_dir();

        use File::Basename;

        use File::Spec;

        my $file_dir = dirname( __FILE__ );

        #say STDERR "file_dir $file_dir";

        use Cwd qw( realpath );

        my $source_rt = "$file_dir" . "/../../../";

        #say STDERR "source_rt $source_rt";

        use File::Spec;

        $source_root = realpath( File::Spec->canonpath( $source_rt ) );

        #$source_root = $source_rt;

        say STDERR "source_root $source_root";
    }

    use lib ( "$source_root" . "/foreign_modules/perl" );
    use lib ( "$source_root" . "/python_scripts/gen-perl" );
}

use Thrift;
use Thrift::BinaryProtocol;
use Thrift::Socket;
use Thrift::BufferedTransport;

use thrift_solr::SolrService;

use thrift_solr::Types;

sub _get_transport
{
    my $socket = new Thrift::Socket( 'localhost', 9090 );
    my $transport = new Thrift::BufferedTransport( $socket, 1024, 1024 );

    return $transport;
}

sub _get_client
{
    my ( $transport ) = @_;

    my $protocol = new Thrift::BinaryProtocol( $transport );
    my $client   = new thrift_solr::SolrServiceClient( $protocol );

    return $client;
}

sub get_media_counts
{
    my ( $q, $facet_field, $fq, $mincount ) = @_;

    my $transport = _get_transport();
    my $client    = _get_client( $transport );

    $transport->open();

    my $ret = $client->media_counts( $q, $facet_field, $fq, $mincount );

    $transport->close();

    return $ret;
}

1;
