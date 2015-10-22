#!/usr/bin/perl

# start all of the mediacloud-* shards in the solr/ directory

use strict;

use v5.10;

use FindBin;
use Getopt::Long;
use Readonly;

Readonly my $JVM_OPTS => '-server -XX:MaxGCPauseMillis=1000';

sub main
{
    my ( $memory, $host, $zk_host ) = @_;

    Getopt::Long::GetOptions( "memory=s" => \$memory, ) || return;

    $memory ||= 1;

    my $solr_dir = "$FindBin::Bin/..";
    chdir( $solr_dir ) || die( "can't cd to $solr_dir" );

    die( "can't find mediacloud/solr/solr.xml" ) unless ( -f 'mediacloud/solr/solr.xml' );

    chdir( 'mediacloud' ) || die( "unable to cd into mediacloud: $!" );

    my $java_cmd = "java $JVM_OPTS -Dsolr.clustering.enabled=true -Xmx${ memory }g -jar start.jar";

    print STDERR "running $java_cmd ...\n";

    exec( $java_cmd );
}

main();
