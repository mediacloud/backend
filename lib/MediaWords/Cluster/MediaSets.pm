package MediaWords::Cluster::MediaSets;

# cluster based just on media set membership

use strict;

# assign each media to a cluster associated with the first media_set_id to which it belongs
sub get_clusters
{
    my ( $clustering_engine ) = @_;

    my $media_lookup = {};
    my $clusters = [];
    
    for my $media_set ( @{ $clustering_engine->cluster_run->{ query }->{ media_sets } } )
    {
        my $media_ids = [ $clustering_engine->db->query( 
            "select media_id from media_sets_media_map where media_sets_id = ?", 
            $media_set->{ media_sets_id } )->flat ];
        
        my $cluster = { internal_features =>  [], external_features => [], description => $media_set->{ name } };
        for my $media_id ( @{ $media_ids } )
        {
            if ( !$media_lookup->{ $media_id } )
            {
                $cluster->{ centroid_media_id } ||= $media_id;
                push( @{ $cluster->{ media_ids } }, $media_id );
                $media_lookup->{ $media_id } = 1;
            }            
        }
        
        push( @{ $clusters }, $cluster );
    }
    
    return $clusters;
}

1;
