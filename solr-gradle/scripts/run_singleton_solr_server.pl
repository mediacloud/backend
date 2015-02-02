#!/usr/bin/perl

# start all of the mediacloud-* shards in the solr/ directory

use strict;

use v5.10;

use FindBin;
use Getopt::Long;

use constant JVM_OPTS => '-XX:MaxGCPauseMillis=1000';

sub main
{
    my ( $memory, $host, $zk_host ) = @_;

    Getopt::Long::GetOptions( "memory=s" => \$memory, ) || return;

    $memory ||= 1;

    my $solr_dir = "$FindBin::Bin/..";
    chdir( $solr_dir ) || die( "can't cd to $solr_dir" );

    die( "can't find mediacloud/solr.xml" ) unless ( -f 'mediacloud/solr.xml' );

    my $gradle_cmd = "JAVA_OPTS=\"" . JVM_OPTS . "\" gradle runSolr -Dsolr.clustering.enabled=true";

    print STDERR "running $gradle_cmd ...\n";

    exec( $gradle_cmd );
}

main();
