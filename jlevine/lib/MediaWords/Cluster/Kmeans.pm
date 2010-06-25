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

sub _k_recurse
{
    my ($nodes, $old_clusters, $n) = @_;
    
    my $new_clusters = [];
    my $reassigned = 0;
    
    # rebuild new_clusters
    for my $old_cluster (@{ $old_clusters })
    {
        my $new_cluster = {
            cluster_id => $old_cluster->{ cluster_id },
            centroid   => $old_cluster->{ centroid }
        };
        push @{ $new_clusters }, $new_cluster;
    }
    
    # Reassign clusters
    for my $node ( @{ $nodes } )
    {   
        $node->{ score } = 0;
        my $old_cluster_id = $node->{ cluster };
        
        for my $cluster ( @{ $new_clusters } )
        {
            my $dp = $node->{ vector }->dot( $cluster->{ centroid } );
            if ($dp > $node->{ score })
            {
                $node->{ score }   = $dp;
                $node->{ cluster } = $cluster->{ cluster_id };
            }
        }
        
        $reassigned++ unless $node->{ cluster } == $old_cluster_id;
    
        push @{ $new_clusters->[ $node->{ cluster } ]->{ nodes } }, $node;
    }
    
    for my $cluster (@{ $new_clusters })
    {
        # Find the "average vector"
        my $avg_vector = Math::SparseVector->new;
        for my $node (@{ $cluster->{ nodes } }) {
            $avg_vector->add( $node->{ vector } );
        }
        
        my $num_vecs = scalar @{ $cluster->{ nodes } };
        if ($num_vecs)
        {    
            $avg_vector->div( $num_vecs );
    
            # Make the new centroid the vector closest to the average
            my $max_score = 0;
            for my $node (@{ $cluster->{ nodes } })
            {
                my $dp = $node->{ vector }->dot( $avg_vector );
                if ($dp > $max_score)
                {
                    $max_score = $dp;
                    $cluster->{ centroid } = $node->{ vector };
                }
            }
        } else {
            $cluster->{ centroid } = Math::SparseVector->new;
        }
    }

    _dump_clusters($new_clusters, $n);
    
    print STDERR "\nFinished k-recurse $n; $reassigned reassigned\n\n";
    
    # TODO: Break if nothing's been reassigned
    unless ($n and $reassigned) {
        return $new_clusters;
    } else {
        return _k_recurse($nodes, $new_clusters, $n - 1);
    }
}

sub _run_kmeans
{
    my ($matrix, $row_labels, $k, $n) = @_;
    
    my $nodes = [];
    my $clusters = [];
    
    # Pick random nodes to seed clusters
    my $cluster_cnt = 0;
    for my $rand ( Math::Random::random_uniform_integer($k, 0, $#{ $matrix }) ) {
        push @{ $clusters }, {
            centroid   => $matrix->[$rand],
            cluster_id => $cluster_cnt++
        };
    }
    
    # Push node onto node array
    for my $i (0 .. $#{ $matrix })
    {
        my $node = {
            vector   => $matrix->[$i],
            media_id => $row_labels->[$i]
        };
        
        push @{ $nodes }, $node;
    }
    
    return _k_recurse($nodes, $clusters, $n);
}

sub get_clusters {
    
    # $matrix => Sparse stem matrix from Cluster::_get_sparse_matrix
    # $k => number of clusters to generate
    # $n => number of iterations
    
    my ( $matrix, $row_labels, $k, $n ) = @_;

    die "You can't have more clusters than sources!\n" if ($k >= $#{ $matrix });

    my $clusters = _run_kmeans($matrix, $row_labels, $k, $n);

    # Turn raw clusters into nice clusters, which should really look like (at least)
    # { media_ids => [],
    #   internal_features =>  [ { stem => stem, term => term , weight => weight } ],
    #   external_features =>  [ { stem => stem, term => term , weight => weight } ] }
    my $nice_clusters = [];
    for my $i (0 .. $#{ $clusters })
    {
        $nice_clusters->[$i] = {};
        my $cluster = $clusters->[$i];
        for my $node (@{ $cluster->{ nodes } })
        {
            push @{ $nice_clusters->[$i]->{ media_ids } }, $node->{ media_id };
        }
    }
    
    # TODO: implement internal and external features
    map { $_->{ internal_features } = []; $_->{ external_features } = []; } @{ $nice_clusters };
    map { $_->{ internal_zscore } = []; $_->{ external_zscore } = []; } @{ $nice_clusters };
    # Also internal/external similarity, zscores, etc...
    
    print STDERR "\n\n Kmeans Klusters: " . Dumper($nice_clusters) . "\n\n";
    
    return $nice_clusters;
}

1;