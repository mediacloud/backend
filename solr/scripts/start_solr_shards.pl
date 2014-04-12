#!/usr/bin/perl

# start all of the mediacloud-* shards in the solr/ directory

use strict;

use v5.10;

use FindBin;
use Getopt::Long;

sub main
{
    my ( $memory, $host, $zk_host ) = @_;

    Getopt::Long::GetOptions(
        "memory=s"  => \$memory,
        "host=s"    => \$host,
        "zk_host=s" => \$zk_host,
    ) || return;

    die( "usage: $0 --memory <gigs of memory for java heap> --host <local hostname> --zk_host <zk host in host:port format>"
    ) unless ( $memory && $zk_host );

    my $solr_dir = "$FindBin::Bin/..";
    chdir( $solr_dir ) || die( "can't cd to $solr_dir" );

    die( "can't find mediacloud/solr/solr.xml" ) unless ( -f 'mediacloud/solr/solr.xml' );

    opendir( DIR, "." ) || die( "unable to open dir $solr_dir: $!" );

    my $shard_dirs = [ grep { $_ =~ /^mediacloud-shard-[0-9]+$/ } readdir( DIR ) ];

    die( "no shard dirs found in $solr_dir" ) unless ( @{ $shard_dirs } );

    for my $shard_dir ( @{ $shard_dirs } )
    {
        $shard_dir =~ /mediacloud-shard-([0-9]+)/;
        my $shard_id = $1;

        mkdir( "../logs" ) unless ( -e "../logs" );

        my $log_file = "../logs/$shard_dir.log";

        chdir( $shard_dir ) || die( "unable to cd into $shard_dir: $!" );

        my $log_config = '-Djava.util.logging.config.file=logging.properties';

        if ( -e "master" )
        {
            my $master_memory = ( $memory * 2 );
            system( "java -server -Xmx${ master_memory }g $log_config -Dhost=$host -DzkRun -jar start.jar > $log_file 2>&1 &" );
        }
        else
        {
            my $port = 7980 + $shard_id;
            system(
"java -server -Xmx$memory $log_config -Dhost=$host -Djetty.port=$port -DzkHost=$zk_host -jar start.jar > $log_file 2>&1 &"
            );
        }
        print STDERR "started shard $shard_id logging to $log_file\n";

        chdir( ".." );
    }
}

main();
