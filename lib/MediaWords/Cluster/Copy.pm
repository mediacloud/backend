package MediaWords::Cluster::Copy;
use MediaWords::CommonLibs;


# copy the clustering solution of $cluster_run->copy_source_cluster_run
#
# this is useful for time slice query maps, in which we want the
# clustering run solution just to be the solution of the clustering
# run from which we are taking the time slices

use strict;

# assign each media to a cluster associated with the first media_set_id to which it belongs
sub get_clusters
{
    my ( $clustering_engine ) = @_;

    my $db = $clustering_engine->db;
    
    my $source_cluster_runs_id = $clustering_engine->cluster_run->{ source_media_cluster_runs_id } 
        || die( "no source_media_cluster_runs_id" );
    
    my $source_cluster_run = $db->find_by_id( 'media_cluster_runs', $source_cluster_runs_id );
    
    my $source_clusters = $db->query( 
        "select * from media_clusters where media_cluster_runs_id = ? order by media_clusters_id asc ", 
        $source_cluster_run->{ media_cluster_runs_id } )->hashes;

    my $dest_clusters = [];
    for my $source_cluster ( @{ $source_clusters } )
    {
        my $dest_cluster = { 
            internal_features =>  [], 
            external_features => [], 
            description => $source_cluster->{ description },
            centroid_media_id => $source_cluster->{ centroid_media_id } };
           
        $dest_cluster->{ media_ids } = [ $db->query( 
            "select media_id from media_clusters_media_map where media_clusters_id = ?",
            $source_cluster->{ media_clusters_id } )->flat ];
            
        push( @{ $dest_clusters }, $dest_cluster );
    }

    return $dest_clusters;
}

1;
