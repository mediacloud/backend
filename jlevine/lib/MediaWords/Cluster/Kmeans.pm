package MediaWords::Cluster::Kmeans; 

# Jon's implementation of the k-means clustering algorithm

use strict;
use Data::Dumper;
use Math::Random;
use MediaWords::Util::Timing qw( start_time stop_time );
use MediaWords::Util::SparseVector qw( vector_add vector_dot vector_div vector_norm vector_normalize );


# Dumps the clusters, but not their vectors
sub _dump_clusters
{
    my ($clusters, $iter) = @_;
    print STDERR "\n\n ITERATION $iter: \n" if $iter;
    
    for my $cluster (@{ $clusters })
    {
        print STDERR "Cluster " . $cluster->{ cluster_id } . ": \n";
        my $center = vector_norm( $cluster->{ centroid } ) || 0;
        print STDERR "  centroid sum: $center\n";
        for my $node (@{ $cluster->{ nodes } })
        {
            print STDERR "  node " . $node->{ media_id } . " = { \n";
            print STDERR "     score   => " . $node->{ score } . "\n";
            print STDERR "     cluster => " . $node->{ cluster } . "\n";
            print STDERR "  }, \n"
        }
        print STDERR "\n";
    }
}

# Given a list of nodes, assigns them to a bunch of empty clusters with centers
sub _assign_nodes
{
    my ($nodes, $clusters) = @_;
    
    my $reassigned = 0;
    for my $node ( @{ $nodes } )
    {   
        $node->{ score } = 0; # reset node's internal z-score
        my $old_cluster_id = $node->{ cluster }; # will be undefined the first time through
        
        for my $cluster ( @{ $clusters } )
        {
            my $dp = vector_dot( $node->{ vector }, $cluster->{ centroid } );
            if ($dp >= $node->{ score }) # must be >= to ensure the score gets updated
            {
                $node->{ score }   = $dp;
                $node->{ cluster } = $cluster->{ cluster_id };
            }
        }
        
        $reassigned++ unless (defined $old_cluster_id and $node->{ cluster } == $old_cluster_id);
        
        # Push node onto the right cluster
        for my $cluster (@{ $clusters })
        {   
            push @{ $cluster->{ nodes } }, $node if $node->{ cluster } == $cluster->{ cluster_id };
        }
    }
    
    return ($nodes, $clusters, $reassigned);
}

# Given a list of clusters, returns new empty clusters with updated centers
sub _find_center
{
    my ($old_clusters) = @_;
    my $new_clusters = [];
    
    for my $old_cluster (@{ $old_clusters })
    {
        my $new_cluster = {
            cluster_id => $old_cluster->{ cluster_id }
        };
        
        # Find the "average vector"
        my $avg_vector = {};
        for my $node (@{ $old_cluster->{ nodes } }) {
            $avg_vector = vector_add( $avg_vector, $node->{ vector } );
        }
        
        my $num_vecs = scalar @{ $old_cluster->{ nodes } };
        if ($num_vecs)
        {    
            $avg_vector = vector_div( $avg_vector, $num_vecs );
    
            # Make the new centroid the vector closest to the average
            my $max_score = 0;
            for my $node (@{ $old_cluster->{ nodes } })
            {
                my $dp = vector_dot( $node->{ vector }, $avg_vector );
                if ($dp > $max_score)
                {
                    $max_score = $dp;
                    $new_cluster->{ centroid } = $node->{ vector };
                }
            }
        } else {
            $new_cluster->{ centroid } = {};
        }
        
        push @{ $new_clusters }, $new_cluster;
    }
    
    return $new_clusters;
}

sub _k_recurse
{
    # Take in the node list, a bunch of empty clusters with centers, and the number of times left to recurse
    my ($nodes, $clusters, $n) = @_;
    
    # Reassign clusters
    ($nodes, $clusters, my $reassigned) = _assign_nodes($nodes, $clusters);
    # _dump_clusters($clusters, $n);
    
    print STDERR "K-means iteration $n: $reassigned reassigned.\n";
    
    # Break if no reassignments, or we've looped enough times
    return $clusters unless ($n and $reassigned);
    
    return _k_recurse($nodes, _find_center($clusters), $n - 1);
}

# Pick nodes to seed clusters
# Could be done randomly--or with k++?
sub _seed_clusters
{
    my ($matrix, $nodes, $k) = @_;
    my $clusters = [];
    my $cluster_cnt = 0;
    
    for my $rand ( Math::Random::random_uniform_integer($k, 0, $#{ $matrix }) ) {
        push @{ $clusters }, {
            centroid   => $matrix->[$rand],
            cluster_id => $cluster_cnt++
        };
    }
    
    return $clusters;
}

# Turn raw clusters into nice clusters, which should really look like (at least)
# { media_ids         => [],
#   internal_features => [ { stem => stem, term => term , weight => weight } ],
#   external_features => [ { stem => stem, term => term , weight => weight } ],
#   internal_zscores  => [], 
#   external_zscores  => [] }
sub _make_nice_clusters
{
    my ($clusters, $col_labels, $stems) = @_;
    
    my $nice_clusters = [];
    for my $cluster (@{ $clusters })
    {
        # TODO: implement internal and external features, zscores, etc...
        my $nice_cluster = {
            media_ids         => [],
            internal_features => [],
            external_features => [],
            internal_zscores  => [],
            external_zscores  => []
        };
        
        # Add "internal features"--just the word frequencies for the centroid
        my $features = [];
        for my $key (keys %{ $cluster->{ centroid } })
        {
            my $stem = $col_labels->[$key];
            my $feature = {
                stem   => $stem,
                term   => $stems->FETCH( $stem ),
                weight => $cluster->{ centroid }->{ $key }
            };
            
            push @{ $features }, $feature;
        }
    
        # Sort the internal features by weight
        my @all_sorted_features = sort { $b->{ weight } <=> $a->{ weight } } @{ $features };
        @{ $nice_cluster->{ internal_features } } = @all_sorted_features[0..50];
        
        # Add the media IDs and their corresponding scores
        for my $node (@{ $cluster->{ nodes } })
        {
            push @{ $nice_cluster->{ media_ids } }, $node->{ media_id };
            push @{ $nice_cluster->{ internal_zscores } }, $node->{ score };
        }        
        
        push @{ $nice_clusters }, $nice_cluster;
    }
    
    # print STDERR "\n\n Kmeans Klusters: " . Dumper($nice_clusters) . "\n\n";
    
    return $nice_clusters;
}

# Public function for the module
# Returns the k-means clusters
sub get_clusters
{    
    # $matrix => Sparse stem matrix from Cluster::_get_sparse_matrix
    # $k => number of clusters to generate
    # $n => number of times to run algorithm
    my ( $matrix, $row_labels, $col_labels, $stems, $k, $n ) = @_;
    die "You can't have more clusters than sources!\n" if ($k >= $#{ $matrix });
    
    # refactor matrix into nodes
    my $nodes = [];
    for my $i (0 .. $#{ $matrix })
    {
        my $node = {
            vector   => $matrix->[$i],
            media_id => $row_labels->[$i]
        };
        push @{ $nodes }, $node if vector_norm( $node->{ vector } ) > 0; # make sure we have data for this node
    }
    
    # time cluster run
    my $t0 = start_time( 'cluster run 1' );
    my $clusters = _k_recurse($nodes, _seed_clusters($matrix, $nodes, $k), $n);
    stop_time( 'cluster run 1', $t0);
    print STDERR "Cluster run 1 score: [TODO]\n\n";    
    
    return _make_nice_clusters($clusters, $col_labels, $stems);
}

1;
