package MediaWords::Cluster::Kmeans;

# Jon's implementation of the k-means clustering algorithm

use strict;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Data::Dumper;
use Math::Random;
use MediaWords::Util::Timing qw( start_time stop_time );
use MediaWords::Util::BigPDLVector qw( vector_new vector_add vector_dot vector_div vector_norm
  vector_normalize vector_length vector_nnz vector_get vector_set );

# Dumps the clusters, but not their vectors
sub _dump_clusters
{
    my ( $clusters, $iter ) = @_;
    print STDERR "\n\n ITERATION $iter: \n" if $iter;

    for my $cluster ( @{ $clusters } )
    {
        print STDERR "Cluster " . $cluster->{ cluster_id } . ": \n";
        my $center = vector_norm( $cluster->{ centroid } ) || 0;
        print STDERR "  centroid norm: $center\n";
        for my $node ( @{ $cluster->{ nodes } } )
        {
            print STDERR "  node " . $node->{ media_id } . " = { \n";
            print STDERR "     score   => " . $node->{ score } . "\n";
            print STDERR "     cluster => " . $node->{ cluster } . "\n";
            print STDERR "  }, \n";
        }
        print STDERR "\n";
    }
}

# Given a list of nodes, assigns them to a bunch of empty clusters with centers
sub _assign_nodes
{
    my ( $nodes, $clusters ) = @_;

    my $reassigned = 0;
    for my $node ( @{ $nodes } )
    {
        $node->{ score } = 0;    # reset node's internal z-score
        my $old_cluster_id = $node->{ cluster };    # will be undefined the first time through

        for my $cluster ( @{ $clusters } )
        {
            my $dp = vector_dot( $node->{ vector }, $cluster->{ centroid } );
            if ( $dp >= $node->{ score } )          # must be >= to ensure the score gets updated
            {
                $node->{ score }   = $dp;
                $node->{ cluster } = $cluster->{ cluster_id };
            }
        }

        $reassigned++ unless ( defined $old_cluster_id and $node->{ cluster } == $old_cluster_id );

        # Push node onto the right cluster
        for my $cluster ( @{ $clusters } )
        {
            push @{ $cluster->{ nodes } }, $node if $node->{ cluster } == $cluster->{ cluster_id };
        }
    }

    return ( $nodes, $clusters, $reassigned );
}

# Given a list of clusters, returns new empty clusters with updated centers
sub _find_center
{
    my ( $old_clusters ) = @_;
    my $new_clusters = [];

    for my $old_cluster ( @{ $old_clusters } )
    {
        my $new_cluster = { cluster_id => $old_cluster->{ cluster_id } };

        # Find the "average vector"
        my $length     = vector_length $old_cluster->{ centroid };
        my $avg_vector = vector_new( $length );
        for my $node ( @{ $old_cluster->{ nodes } } )
        {
            $avg_vector = vector_add( $avg_vector, $node->{ vector } );
        }

        my $num_vecs = scalar @{ $old_cluster->{ nodes } };
        if ( $num_vecs )
        {
            $avg_vector = vector_div( $avg_vector, $num_vecs );

            # Make the new centroid the vector closest to the average
            my $max_score = 0;
            for my $node ( @{ $old_cluster->{ nodes } } )
            {
                my $dp = vector_dot( $node->{ vector }, $avg_vector );
                if ( $dp > $max_score )
                {
                    $max_score                    = $dp;
                    $new_cluster->{ centroid }    = $node->{ vector };
                    $new_cluster->{ centroid_media_id } = $node->{ media_id };
                }
            }
        }
        else
        {
            next unless defined $new_cluster->{ centroid };
            my $length = vector_length $new_cluster->{ centroid };
            $new_cluster->{ centroid } = vector_new( $length );
        }

        push @{ $new_clusters }, $new_cluster;
    }

    return $new_clusters;
}

sub _k_recurse
{

    # Take in the node list, a bunch of empty clusters with centers, and the number of times left to recurse
    my ( $nodes, $clusters, $num_iterations ) = @_;

    # Reassign clusters
    ( $nodes, $clusters, my $reassigned ) = _assign_nodes( $nodes, $clusters );

    # _dump_clusters($clusters, $num_iterations);

    print STDERR "K-means iteration $num_iterations: $reassigned reassigned.\n";

    # Break if no reassignments, or we've looped enough times
    return $clusters unless ( $num_iterations and $reassigned );

    return _k_recurse( $nodes, _find_center( $clusters ), $num_iterations - 1 );
}

# Pick random nodes to seed clusters
sub _seed_clusters_random
{
    my ( $nodes, $num_clusters ) = @_;
    my $clusters    = [];
    my $cluster_cnt = 0;

    for my $rand ( Math::Random::random_uniform_integer( $num_clusters, 0, $#{ $nodes } ) )
    {
        push @{ $clusters },
          {
            centroid    => $nodes->[ $rand ]->{ vector },
            centroid_media_id => $nodes->[ $rand ]->{ media_id },
            cluster_id  => $cluster_cnt++
          };
    }

    return $clusters;
}

# Use the K-Means++ algorithm to seed clusters: http://en.wikipedia.org/wiki/K-means%2B%2B
# 1) Pick a starting centroid at random
# 2) Traverse over every node, and find the one least similar to current clusters
# 3) Make that node the centroid of a new cluster
# 4) Repeat 2-3 until you have 'k' clusters
sub _seed_clusters_plus_plus
{
    my ( $nodes, $num_clusters ) = @_;
    my $clusters    = [];
    my $cluster_cnt = 0;

    my $t0 = start_time( 'k-means++' );

    # Pick one random starting centroid
    my $first_center = Math::Random::random_uniform_integer( 1, 0, $#{ $nodes } );
    push @{ $clusters },
      {
        centroid    => $nodes->[ $first_center ]->{ vector },
        centroid_media_id => $nodes->[ $first_center ]->{ media_id },
        cluster_id  => $cluster_cnt++
      };

    # Add $num_clusters-1 centroids
    while ( $cluster_cnt < $num_clusters )
    {
        my $new_centroid;
        my $new_centroid_media_id;
        my $least_cluster_sim = 1;

        # Look at each node, and determine the distance D(x) to the closest cluster
        for my $node ( @{ $nodes } )
        {
            my $max_cluster_sim = 0;

            for my $cluster ( @{ $clusters } )
            {
                my $cluster_sim = vector_dot( $node->{ vector }, $cluster->{ centroid } );
                $max_cluster_sim = $cluster_sim if $cluster_sim > $max_cluster_sim;
            }

            # Make this node the new centroid if it's the least similar to other nodes
            if ( $max_cluster_sim < $least_cluster_sim )
            {
                $least_cluster_sim = $max_cluster_sim;
                $new_centroid      = $node->{ vector };
                $new_centroid_media_id   = $node->{ media_id };
            }
        }

        # my $sum_scores = sum (map {$_ ** 2} @{ $cluster_scores });

        push @{ $clusters },
          {
            centroid    => $new_centroid,
            centroid_media_id => $new_centroid_media_id,
            cluster_id  => $cluster_cnt++
          };
    }

    stop_time( 'k-means++', $t0 );

    return $clusters;
}

# Perhaps closer to the real k-means++ algorithm...
# 1) Pick a random node as the first cluster
# 2) Go over every node and pretend it's the centroid of a cluster
# 3) Then sum up D(x) for every x in X
#     ie. For every node, find the min distance to the nearest cluster, then sum those distances
# 4) Choose the node that minimizes this sum--err what? Add that to the clusters?
# 5) Repeat 2-4?
sub _seed_clusters_plus_plus2
{
    my ( $nodes, $num_clusters ) = @_;
    my $clusters    = [];
    my $cluster_cnt = 0;

    my $t0 = start_time( 'k-means++' );

    # Pick one random starting centroid
    my $first_center = Math::Random::random_uniform_integer( 1, 0, $#{ $nodes } );
    push @{ $clusters },
      {
        centroid    => $nodes->[ $first_center ]->{ vector },
        centroid_media_id => $nodes->[ $first_center ]->{ media_id },
        cluster_id  => $cluster_cnt++
      };

    # Add $num_clusters-1 centroids
    while ( $cluster_cnt < $num_clusters )
    {
        my $best_cluster = {
            centroid    => undef,
            centroid_media_id => undef,
            cluster_id  => $cluster_cnt++
        };

        my $min_score;

        # Consider each node as a center
        for my $node ( @{ $nodes } )
        {
            my $new_clusters = [];
            @{ $new_clusters } = @{ $clusters };    # deep copy...
            $best_cluster->{ centroid }    = $node->{ vector };
            $best_cluster->{ centroid_media_id } = $node->{ media_id };
            push @{ $new_clusters }, @{ $best_cluster };

            my $sum_scores = 0;

            # Now look at each node, and add the distance D(x) to the total
            for my $inner_node ( @{ $nodes } )
            {
                my $max_cluster_sim = 0;

                for my $cluster ( @{ $new_clusters } )
                {
                    my $cluster_sim = vector_dot( $inner_node->{ vector }, $cluster->{ centroid } );
                    $max_cluster_sim = $cluster_sim if $cluster_sim > $max_cluster_sim;
                }

                $sum_scores += $max_cluster_sim;
            }

            unless ( defined $min_score and $min_score < $sum_scores )
            {
                $min_score    = $sum_scores;
                $best_cluster = pop @{ $new_clusters };
            }
        }

        push @{ $clusters }, $best_cluster;
    }

    stop_time( 'k-means++', $t0 );

    return $clusters;
}

# Turn the unweidly matrix data structure into the friendlier 'nodes' data structure, with media id labels!
sub _refactor_matrix_into_nodes
{
    my ( $matrix, $criterion_matrix, $row_labels ) = @_;

    my $nodes = [];
    for my $i ( 0 .. $#{ $matrix } )
    {
        my $node = {
            vector           => $matrix->[ $i ],
            criterion_vector => $criterion_matrix->[ $i ],
            media_id         => $row_labels->[ $i ]
        };

        my $media_id          = $node->{ media_id };
        my $vector_non_zeroes = scalar @{ vector_nnz $node->{ vector } };
        my $vector_length     = vector_length $node->{ vector };
        print STDERR "Media ID $media_id has non-zeroes/length: $vector_non_zeroes / $vector_length\n";

        push @{ $nodes }, $node if $vector_non_zeroes > 0;    # make sure we have data for this node
    }

    return $nodes;
}

# Use the I2 'clustering criterion function' to come up with a score for the cluster run
sub _eval_clusters_i2
{
    my ( $clusters ) = @_;
    my $total_score = 0;

    # my $total_criterion_score = 0;

    for my $cluster ( @{ $clusters } )
    {
        my $cluster_score = 0;

        # my $criterion_score = 0;
        my $nodes = $cluster->{ nodes };

        for my $i ( 0 .. $#{ $nodes } )
        {
            for my $j ( $i .. $#{ $nodes } )
            {
                $cluster_score += vector_dot( $nodes->[ $i ]->{ vector }, $nodes->[ $j ]->{ vector } );

                # $criterion_score += vector_dot( $nodes->[$i]->{ criterion_vector }, $nodes->[$j]->{ criterion_vector } );
            }
        }

        $total_score += sqrt $cluster_score;

        # $total_criterion_score += sqrt $criterion_score;
    }

    return ( $total_score );    #, $total_criterion_score );
}

# Use the I1 'clustering criterion function' to come up with a score for the cluster run
sub _eval_clusters_normalized
{
    my ( $clusters ) = @_;

    my $total_score  = 0;
    my $num_clusters = scalar @{ $clusters };

    for my $cluster ( @{ $clusters } )
    {
        my $nodes        = $cluster->{ nodes };
        my $num_nodes    = scalar @{ $nodes };
        my $scale_factor = $num_nodes * ( $num_nodes - 1 );

        if ( $scale_factor )
        {

            # get internal sim score
            my $centroid       = $cluster->{ centroid };
            my $internal_score = 0;
            for my $i ( 0 .. $#{ $nodes } )
            {
                for my $j ( $i .. $#{ $nodes } )
                {
                    my $dp = vector_dot( $nodes->[ $i ]->{ vector }, $nodes->[ $j ]->{ vector } );
                    $internal_score += $dp / $scale_factor unless ( $dp == 1 );
                }
            }

            # get external sim score
            my $external_score = 0;
            for my $comp_cluster ( @{ $clusters } )
            {
                my $dp = vector_dot( $centroid, $comp_cluster->{ centroid } );
                $external_score += $dp / ( $num_clusters - 1 ) unless ( $dp == 1 );
            }

            $total_score += ( $internal_score / $external_score ) / $num_clusters unless ( $external_score == 0 );

            print STDERR "num nodes: $num_nodes; internal score: $internal_score; external_score: $external_score\n";
        }
    }

    print STDERR "total score: $total_score\n\n";

    return ( $total_score );    #, $total_criterion_score );
}

# Print out some stats about the scores
sub _eval_scores
{
    my ( $scores ) = @_;

    my $max_score  = $scores->[ 0 ];
    my $min_score  = $scores->[ 0 ];
    my $sum_scores = 0;

    for my $score ( @{ $scores } )
    {
        $max_score = $score if $score >= $max_score;
        $min_score = $score if $score <= $min_score;
        $sum_scores += $score;
    }

    my $avg_score = $sum_scores / scalar @{ $scores };

    print STDERR "Max score: $max_score; min score: $min_score; average score: $avg_score\n";

}

# Do a bunch of cluster runs and return the best one
sub _get_best_cluster_run
{
    my ( $nodes, $num_clusters, $num_iterations, $num_cluster_runs ) = @_;

    my $best_clusters = {};
    my $best_score    = 0;
    my $score_list    = [];

    # my $criterion_score_list = [];
    my $score_list_normalized = [];

    for my $i ( 0 .. $num_cluster_runs )
    {
        my $t0 = start_time( "cluster run $i" );    # time cluster run
        my $clusters = _k_recurse( $nodes, _seed_clusters_random( $nodes, $num_clusters ), $num_iterations );
        stop_time( "cluster run $i", $t0 );

        my ( $score )            = _eval_clusters_i2( $clusters );
        my ( $score_normalized ) = _eval_clusters_normalized( $clusters );
        push @{ $score_list },            $score;
        push @{ $score_list_normalized }, $score_normalized;

        # push @{ $criterion_score_list }, $criterion_score;
        print STDERR "Cluster run $i regular score: $score\n\n";    #  criterion score: $criterion_score\n\n";

        if ( $score > $best_score )
        {
            $best_score    = $score;
            $best_clusters = $clusters;
        }
    }

    print STDERR "(Regular scores) ";
    _eval_scores( $score_list );
    print STDERR "(normalized scores) ";
    _eval_scores( $score_list_normalized );

    # print STDERR "(Criterion scores) ";
    # _eval_scores($criterion_score_list);

    return $best_clusters;
}

# Turn raw clusters into nice clusters for writing to the database, which should really look like (at least)
# { media_ids         => [],
#   centroid_media_id       => $centroid_media_id,
#   internal_features => [ { stem => stem, term => term , weight => weight } ],
#   external_features => [ { stem => stem, term => term , weight => weight } ],
#   internal_zscores  => [],
#   external_zscores  => [] }
sub _make_nice_clusters
{
    my ( $clusters, $col_labels, $stems ) = @_;

    my $nice_clusters = [];
    for my $cluster ( @{ $clusters } )
    {

        # TODO: implement internal and external features, zscores, etc...
        my $nice_cluster = {
            media_ids         => [],
            centroid_media_id       => $cluster->{ centroid_media_id },
            internal_features => [],
            external_features => [],
            internal_zscores  => [],
            external_zscores  => []
        };

        # Add "internal features"--just the word frequencies for the centroid
        my $features = [];
        for my $key ( @{ vector_nnz $cluster->{ centroid } } )
        {
            my $stem    = $col_labels->[ $key ];
            my $feature = {
                stem   => $stem,
                term   => $stems->FETCH( $stem ),
                weight => vector_get( $cluster->{ centroid }, $key )
            };

            push @{ $features }, $feature;
        }

        # Sort the internal features by weight
        my @all_sorted_features = sort { $b->{ weight } <=> $a->{ weight } } @{ $features };
        @{ $nice_cluster->{ internal_features } } = @all_sorted_features[ 0 .. 50 ];

        # Add the media IDs and their corresponding scores
        for my $node ( @{ $cluster->{ nodes } } )
        {
            push @{ $nice_cluster->{ media_ids } },        $node->{ media_id };
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
    my ( $matrix, $criterion_matrix, $row_labels, $col_labels, $stems, $num_clusters, $num_iterations, $num_cluster_runs ) =
      @_;
    die "You can't have more clusters than sources!\n" if ( $num_clusters >= $#{ $matrix } );

    my $nodes = _refactor_matrix_into_nodes( $matrix, $criterion_matrix, $row_labels );
    my $best_clusters = _get_best_cluster_run( $nodes, $num_clusters, $num_iterations, $num_cluster_runs );
    my $nice_clusters = _make_nice_clusters( $best_clusters, $col_labels, $stems );

    return $nice_clusters;
}

# Given a new list of nodes and some clusters, get a new set of clusters with the same
#   media_ids and all that but new (smaller) vectors
#   You really only need to copy over $cluster->{ nodes }...
sub _get_new_clusters_from_old
{
    my ( $new_nodes, $old_clusters ) = @_;
    my $new_clusters = [];

    for my $old_cluster ( @{ $old_clusters } )
    {
        my $cluster_nodes = [];

        for my $medium ( @{ $old_cluster->{ media_ids } } )
        {
            for my $node ( @{ $new_nodes } )
            {
                push @{ $cluster_nodes }, $node if $medium == $node->{ media_id };
            }
        }

        push @{ $new_clusters },
          {
            centroid    => $old_cluster->{ centroid },
            centroid_media_id => $old_cluster->{ centroid_media_id },
            nodes       => $cluster_nodes
          };
    }

    return $new_clusters;
}

# Given a matrix, presumably with more non-zero columns than the last one,
#   score it based on the clusters from another cluster run with a (presumably)
#   different matrix. The point is to do a cluster run with 100-word vectors
#   then see what those scores are like with 500-word vectors.
sub get_score_from_old_run
{
    my ( $big_matrix, $row_labels, $old_clusters ) = @_;

    my $new_nodes = _refactor_matrix_into_nodes( $big_matrix, $row_labels );
    my $new_clusters = _get_new_clusters_from_old( $new_nodes, $old_clusters );
    my $score = _eval_clusters_i2 $new_clusters;

    return $score;
}

1;
