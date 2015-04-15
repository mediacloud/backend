#!/usr/bin/perl

# loading a new config (solrconfig.xml or schema.xml or others in conf/) requires first loading the
# config files into zookeeper and then telling each shard to reload its config from zookeeper.
# this script takes care of both of those steps, assuming that the shards were created by
# create_solr_shards.pl.

use strict;

use v5.10;

use FindBin;
use Getopt::Long;
use LWP::UserAgent;

# call script that loads shard 1 config files into zookeeper
sub call_zk_load
{
    my ( $host ) = @_;
    
    print STDERR "loading config into zk ...\n";
    
    my $cmd = <<END;
mediacloud-shard-1/cloud-scripts/zkcli.sh -cmd upconfig -zkhost  $host:9983  -collection collection1 -confname mediacloud -solrhome solr -confdir mediacloud-shard-1/solr/collection1/conf
END

    use autodie ( 'system' );
    system( $cmd );    
}


# submit reload request to the solr server on the given host and port
sub call_reload
{
    my ( $host, $port ) = @_;
    
    print STDERR "reloading $host / $port ...\n";
    
    my $ua = LWP::UserAgent->new;
    
    my $url = "http://$host:$port/solr/admin/cores?action=RELOAD&core=collection1";
    
    my $res = $ua->get( "http://$host:$port/solr/admin/cores?action=RELOAD&core=collection1" );
    
    die( "reload failed for $host / $port: " . $res->as_string ) unless ( $res->is_success );
}

sub main
{
    my ( $num_shards, $hosts, $zk_host ) = @_;

    Getopt::Long::GetOptions(
        "num_shards=i"  => \$num_shards,
        "host=s@"        => \$hosts,
        "zk_host=s"     => \$zk_host,
    ) || return;

    die(
        "usage: $0 --num_shards < total number of shards > --zk_host < zoo keeper host > [ --host < host > ... ]" )
      unless ( $num_shards && $zk_host );
      
    $hosts ||= [];

    my $solr_dir = "$FindBin::Bin/..";
    chdir( $solr_dir ) || die( "can't cd to $solr_dir" );

    die( "can't find solr/mediacloud-shard-1/solr/solr.xml" ) unless ( -f 'mediacloud-shard-1/solr/solr.xml' );
    
    call_zk_load( $zk_host );

    my $num_hosts = @{ $hosts } + 1;
    my $num_shards_per_host = $num_shards / $num_hosts;
    die( "num_shards '$num_shards' must be divisible by number of hosts ($num_hosts)" )
        unless ( $num_shards_per_host == int( $num_shards_per_host ) );

    call_reload( $zk_host, 8983 );
    for ( my $i = 2; $i <= $num_shards_per_host; $i++ )
    {
        call_reload( $zk_host, 7980 + $i );
    }
    
    for my $host ( @{ $hosts } )
    {
        for ( my $i = 1; $i <= $num_shards_per_host; $i++ )
        {
            call_reload( $host, 7980 + $i );
        }
    }
}

main();
