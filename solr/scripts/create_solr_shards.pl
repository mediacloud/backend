#!/usr/bin/perl

# create local solr shard directories for the given number of shards by copying the solr/mediacloud directory.
# if num_total_shards is specified, run the first shard once to initialize the master/zk shard.
#
# usage: create_solr_shards.pl --local_shards <num local shards> --total_shards <num total shards>

use strict;

use FindBin;
use Getopt::Long;

sub main
{
    my ( $local_shards, $total_shards ) = @_;

    Getopt::Long::GetOptions(
        "local_shards=i" => \$local_shards,
        "total_shards=i" => \$total_shards,
    ) || return;

    die( "usage: $0 --local_shards <num local shards> [ --total_shards <num total shards> ]" )
        unless ( $local_shards );
        
    die( "local_shards must be > 0" ) unless ( $local_shards > 0 );
    
    die( "total shards must be >= local shards" ) if ( $total_shards && ( $total_shards < $local_shards ) );

    my $solr_dir = "$FindBin::Bin/..";
    chdir( $solr_dir ) || die( "can't cd to $solr_dir" );
    
    die( "can't find mediacloud/solr/solr.xml" ) unless ( -f 'mediacloud/solr/solr.xml' );
      
    print STDERR "creating shard directories...\n";
            
    for my $i ( 1 .. $local_shards )
    {
        die( "shard directory mediacloud-shard-$i already exists" ) if ( -e "mediacloud-shard-$i" );
    }
      
    for my $i ( 1 .. $local_shards )
    {
        system( "cp -a mediacloud mediacloud-shard-$i" );
    }
    
    return unless ( $total_shards );
    
    print STDERR "initializing main shard...\n";
    
    mkdir( "logs" ) unless ( -e "logs" );

    chdir( "mediacloud-shard-1" ) || die( "can't cd to mediacloud-shard-1" ); 
    
    # create mediacloud-shard-1/master file to indicate that this shard is the cluster master
    open( FILE, ">master") || die( "Unable to open master file: $!" );
    close( FILE );
    
    my $log_file = '../logs/mediacloud-shard-1.log';
    
    system( <<END );
java -DzkRun -DnumShards=$total_shards -Dbootstrap_confdir=./solr/collection1/conf -Dcollection.configName=mediacloud -jar start.jar > $log_file 2>&1 &
END

    my $successful_init;
    CHECKLOG: for ( my $i = 0; $i < 12; $i++ )
    {
        # print STDERR "check log file...\n";
        open( LOG, "< $log_file" ) || die( "unable to open log file $log_file: $!" );
        while ( my $line = <LOG> )
        {
            # print STDERR "check: $line\n";
            if ( $line =~ /org.apache.solr.cloud.Overseer.*Update state numShards/ )
            {
                $successful_init = 1;
                close( LOG );
                last CHECKLOG;
            }
        }
        close( LOG );
        sleep 5;
    }

    if ( $successful_init )
    {
        print STDERR "initialization succeeded\n";
    }
    else
    {
        print STDERR "Unable to find successful init message (org.apache.solr.cloud.Overseer  – Update state numShards=) in $log_file";
    }
        
    my $ps = `ps aux`;
    # print STDERR "$ps\n";
    
    if ( $ps =~ /[^ ]*\s+([0-9]+).*java \-DzkRun \-DnumShards/ )
    {
        my $pid = $1;
        print STDERR "killing java process $pid...\n";
        kill( 'TERM', $pid );
    }
    else
    {
        print STDERR "unable to find process to kill\n";
    }
}

main();