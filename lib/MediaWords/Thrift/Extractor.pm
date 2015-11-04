package MediaWords::Thrift::Extractor;

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# functions for searching the solr server

use JSON;
use List::Util;

use MediaWords::Languages::Language;
use MediaWords::Util::Config;
use MediaWords::Util::Web;
use MediaWords::Util::Process;
use List::MoreUtils qw ( uniq );

BEGIN
{
    use MediaWords::Util::Config;

    use lib MediaWords::Util::Config::get_mc_root_dir() . "/foreign_modules/perl";
    use lib MediaWords::Util::Config::get_mc_root_dir() . "/python_scripts/gen-perl";
}

use Thrift;
use Thrift::BinaryProtocol;
use Thrift::Socket;
use Thrift::BufferedTransport;

use thrift_solr::ExtractorService;

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
    my $client   = new thrift_solr::ExtractorServiceClient( $protocol );

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

sub extract_html
{
    my ( $raw_html ) = @_;

    say STDERR "Extracting with Readability via Thrift...";

    my $transport = _get_transport();
    my $client    = _get_client( $transport );

    my $start_time = time();

    while ( 1 )
    {
        eval { $transport->open(); };

        my $e = $@;
        if ( $e )
        {
            if ( ( time() - $start_time ) < 60 )
            {
                sleep 1;
                say STDERR "Retrying connecting to thrift server";
                next;
            }

            my $error_message = "Giving up trying to connect to thrift server:\n";
            $error_message .= Dumper( $e ) . "\n";
            $error_message .= "Gearman worker is terminating so that the extractor job remains in the Gearman queue";

            fatal_error( $error_message );
        }

        last;
    }

    my $ret = $client->extract_html( $raw_html );

    $transport->close();

    foreach my $html ( @$ret )
    {
        utf8::decode( $html );
    }

    say STDERR "Done extracting with Readability via Thrift.";

    return $ret;
}

1;
