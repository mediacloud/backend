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
    use FindBin;

    my $base_dir = MediaWords::Util::Config::base_dir();
    use lib "$FindBin::Bin/../../../foreign_modules/perl";
    use lib "$FindBin::Bin/../../../python_scripts/gen-perl";
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

    my $protocol  = new Thrift::BinaryProtocol( $transport );
    my $client    = new thrift_solr::SolrServiceClient( $protocol );
    
    return $client;
}

sub get_media_counts
{
    my ( $q, $facet_field, $fq, $mincount ) = @_;

    my $transport = _get_transport();
    my $client    = _get_client( $transport);

    $transport->open();

    my $ret = $client->media_counts( $q, $facet_field, $fq, $mincount );

    $transport->close();

    return $ret;
}

1;
