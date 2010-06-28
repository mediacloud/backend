package MediaWords::Cluster::Kmeans; 

# Jon's implementation of the k-means clustering algorithm

use strict;
use Data::Dumper;
use Math::SparseVector;
use Math::Random;

sub _sum_vector # adds all the entries in a sparse_vector... could be useful for debugging
{
    my ($vec) = @_;
    my @indices = $vec->keys;
    my $total;
    for my $i (@indices) {
        $total += $vec->get($i);
    }
    return $total;
}

sub _dump_clusters # But don't include any actual vectors!
{
    my ($clusters, $iter) = @_;
    print STDERR "\n\n ITERATION $iter: \n" if $iter;
    
    for my $cluster (@{ $clusters })
    {
        print STDERR "Cluster " . $cluster->{ cluster_id } . ": \n";
        my $center = _sum_vector( $cluster->{ centroid } ) || 0;
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
        my $old_cluster_id = $node->{ cluster };
        
        for my $cluster ( @{ $clusters } )
        {
            my $dp = $node->{ vector }->dot( $cluster->{ centroid } );
            if ($dp > $node->{ score })
            {
                $node->{ score }   = $dp;
                $node->{ cluster } = $cluster->{ cluster_id };
            }
        }
        
        $reassigned++ if (defined $old_cluster_id and $node->{ cluster } != $old_cluster_id);
    
        push @{ $clusters->[ $node->{ cluster } ]->{ nodes } }, $node;
    }
    
    return ($nodes, $clusters, $reassigned);
}

# Returns a bunch of empty clusters, but with updated centers
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
        my $avg_vector = Math::SparseVector->new;
        for my $node (@{ $old_cluster->{ nodes } }) {
            $avg_vector->add( $node->{ vector } );
        }
        
        my $num_vecs = scalar @{ $old_cluster->{ nodes } };
        if ($num_vecs)
        {    
            $avg_vector->div( $num_vecs );
    
            # Make the new centroid the vector closest to the average
            my $max_score = 0;
            for my $node (@{ $old_cluster->{ nodes } })
            {
                my $dp = $node->{ vector }->dot( $avg_vector );
                if ($dp > $max_score)
                {
                    $max_score = $dp;
                    $new_cluster->{ centroid } = $node->{ vector };
                }
            }
        } else {
            $new_cluster->{ centroid } = Math::SparseVector->new;
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
    
    # Break if no reassignments, or we've looped enough times
    return $clusters unless ($n and $reassigned);
    
    print STDERR "\nFinished k-recurse after $n iterations; $reassigned reassigned\n\n";
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
    my ($clusters) = @_;
    
    my $nice_clusters = [];
    for my $i (0 .. $#{ $clusters })
    {
        # TODO: implement internal and external features, zscores, etc...
        
        # Get top features for the center of each cluster
        
        $nice_clusters->[$i] = {
            media_ids         => [],
            internal_features => [],
            external_features => [],
            internal_zscores  => [],
            external_zscores  => []
        };
        my $cluster = $clusters->[$i];
        for my $node (@{ $cluster->{ nodes } })
        {
            push @{ $nice_clusters->[$i]->{ media_ids } }, $node->{ media_id };
            push @{ $nice_clusters->[$i]->{ internal_zscores } }, $node->{ score };
        }
    }
    
    print STDERR "\n\n Kmeans Klusters: " . Dumper($nice_clusters) . "\n\n";
    
    return $nice_clusters;
}

sub get_clusters
{    
    # $matrix => Sparse stem matrix from Cluster::_get_sparse_matrix
    # $k => number of clusters to generate
    # $n => number of times to run algorithm
    my ( $matrix, $row_labels, $k, $n ) = @_;
    die "You can't have more clusters than sources!\n" if ($k >= $#{ $matrix });
    
    # refactor matrix into nodes
    my $nodes = [];
    for my $i (0 .. $#{ $matrix })
    {
        my $node = {
            vector   => $matrix->[$i],
            media_id => $row_labels->[$i]
        };
        push @{ $nodes }, $node;
    }
    
    my $clusters = _k_recurse($nodes, _seed_clusters($matrix, $nodes, $k), $n);
    
    my $nice_clusters = _make_nice_clusters($clusters);
    
    return $nice_clusters;
}

1;
