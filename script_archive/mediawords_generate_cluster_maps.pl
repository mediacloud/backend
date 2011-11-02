#!/usr/bin/perl

# generate time slice cluster maps based on media set clustering for the given media sets, dates, and topics

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::Cluster;
use MediaWords::Cluster::Map;
use MediaWords::DB;
use MediaWords::DBI::Queries;

# start and end dates for the cluster query
use constant QUERY_START_DATE => '2010-04-01';
use constant QUERY_END_DATE => '2011-04-01';

# media sets for which to generate maps
use constant MEDIA_SETS => ( 16710, 16711, 16712, 16713, 16714, 16715, 16716, 1878, 4631, 5719 );

# sets of topics to use for the cluster queries
use constant TOPIC_SETS => ( [ 331, 332, 333 ], [ 334, 335, 336, 337 ], [ 338, 339 ], [ 340, 341 ] );

# media set to use as the pole for the maps
use constant POLAR_MEDIA_SET => ( 5719 );

# return hash with the params needed to find or generate the cluster query
sub get_query_params
{
    return {
        start_date => QUERY_START_DATE,
        end_date => QUERY_END_DATE,
        media_sets_ids => [ MEDIA_SETS ]
    };
}

# find a cluster run for the given query or create it if it doesn't exist
sub get_cluster_run
{
    my ( $db, $query ) = @_;
    
    my $cluster_run = $db->query(
        "select * from media_cluster_runs " .
        "  where queries_id = ? and clustering_engine = 'media_sets' ",
        $query->{ queries_id } )->hash;
    
    return $cluster_run if ( $cluster_run );

    my $cluster_run = $db->create( 'media_cluster_runs', {
        queries_id => $query->{ queries_id },
        num_clusters => 1,
        clustering_engine => 'media_sets',
        state => 'pending' } );
        
    my $clustering_engine = MediaWords::Cluster->new( $db, $cluster_run );
    $clustering_engine->execute_and_store_media_cluster_run();
    
    return $cluster_run;
}

# generate a polar cluster map for the given cluster run if it doesn't already
# already exist.
sub get_cluster_map
{
    my ( $db, $cluster_run, $cluster_map ) = @_;
    
    my $polar_query_params = { %{ $cluster_run->{ query } } };
    $polar_query_params->{ media_sets_ids } = POLAR_MEDIA_SET;
    my $polar_query = MediaWords::DBI::Queries::find_or_create_query_by_params( $db, $polar_query_params );

    my $cluster_map = $db->query(
        "select * from media_cluster_maps mcm, media_cluster_map_poles mcmp " .
        "  where media_cluster_runs_id = ? and mcm.media_cluster_maps_id = mcmp.media_cluster_maps_id " .
        "    and mcmp.queries_id = ?",
        $cluster_run->{ media_cluster_runs_id }, $polar_query->{ queries_id } )->hash;
    
    return $cluster_map if ( $cluster_map );

    return MediaWords::Cluster::Map::generate_cluster_map( $db, $cluster_run, 'polar', [ $polar_query ], 1, 'graphviz-neato' );
}

# for the given query params, find or generate overall and time slice cluster maps.
# return the overall cluster map.
sub generate_cluster_maps
{
    my ( $db, $query_params ) = @_;
    
    my $query = MediaWords::DBI::Queries::find_or_create_query_by_params( $db, $query_params );

    my $cluster_run = get_cluster_run( $db, $query );
    $cluster_run->{ query } = $query;
    
    my $cluster_map = get_cluster_map( $db, $cluster_run );
    MediaWords::Cluster::Map::get_time_slice_maps( $db, $cluster_run, $cluster_map );
    
    return $cluster_map;
}

# print amanda url to view time slice cluster maps for given cluster map
sub print_cluster_map_url
{
    my ( $cluster_map ) = @_;

    # print( "http://amanda.law.harvard.edu/admin/clusters/view_time_slice_maps/" . 
    print( "http://metaverse:3000/clusters/view_time_slice_map/" . 
        "$cluster_map->{ media_cluster_runs_id }?media_cluster_maps_id=$cluster_map->{ media_cluster_maps_id }\n" );
}

sub main 
{
    my $db = MediaWords::DB::connect_to_db;
    
    my $query_params = get_query_params();
    
    print_cluster_map_url( generate_cluster_maps( $db, $query_params ) );
    
    for my $topic_set ( TOPIC_SETS )
    {
        $query_params->{ dashboard_topics_ids } = $topic_set;
        
        print_cluster_map_url( generate_cluster_maps( $db, $query_params ) );
    }
}

main();