package MediaWords::Cluster::Map::GraphLayoutAesthetic;
use MediaWords::CommonLibs;


use strict;
use Data::Dumper;
use List::Member;
use Perl6::Say;

use Graph;
use Graph::Layout::Aesthetic;

sub _get_centroids_from_graph
{
    my ( $graph, $media_clusters, $nodes ) = @_;

    my $centroids = [];

    for my $cluster ( @{ $media_clusters } )
    {
        my $cluster_id   = $cluster->{ media_clusters_id };
        my $cluster_name = $cluster->{ description };

        my $xTotal = 0;
        my $yTotal = 0;

        my $num_nodes = 0;

        for my $i ( 0 .. $#{ $nodes } )
        {
            if ( my $node = $nodes->[ $i ] ) 
            {
                if ( $node->{ cluster_id } && ( $node->{ cluster_id } == $cluster_id ) )
                {                                
                    $xTotal += $graph->get_vertex_attribute( $i, "x_coord" );
                    $yTotal += $graph->get_vertex_attribute( $i, "y_coord" );
                    $num_nodes++;
                }
            }
        }

        my $xAvg = $num_nodes ? ( $xTotal / $num_nodes ) : 0;
        my $yAvg = $num_nodes ? ( $yTotal / $num_nodes ) : 0;

        my $centroid = {
            x    => $xAvg,
            y    => $yAvg,
            id   => $cluster->{ media_clusters_id },
            name => $cluster->{ description }
        };

        push @{ $centroids }, $centroid if ( $centroid->{ x } and $centroid->{ y } );
    }

    return $centroids;
}

# Run the actual force layout
sub _run_force_layout_on_graph
{
    my ( $graph, $nodes ) = @_;

    Graph::Layout::Aesthetic->gloss_graph(
        $graph,
        pos_attribute => [ "x_coord", "y_coord" ],
        forces        => {
            node_repulsion  => 1,
            min_edge_length => 1
        }
    );
    
    for my $vertex ( $graph->vertices )
    {
        my $nodes_id = $graph->get_vertex_attribute( $vertex, "nodes_id" );

        $nodes->[ $nodes_id ]->{ x } = $graph->get_vertex_attribute( $vertex, "x_coord" );
        $nodes->[ $nodes_id ]->{ y } = $graph->get_vertex_attribute( $vertex, "y_coord" );
        print STDERR "plot node $nodes_id: $nodes->[ $nodes_id ]->{ x }, $nodes->[ $nodes_id ]->{ y }\n";
    }
}

# Prepare the graph by adding nodes and links to it
sub _add_nodes_and_links_to_graph
{
    my ( $nodes ) = @_;

    my $graph = Graph::Undirected->new;

    for my $node ( @{ $nodes } )
    {
        if ( defined( $node->{ nodes_id } ) )
        {
            $graph->add_vertex( $node->{ nodes_id } );
            $graph->set_vertex_attribute( $node->{ nodes_id }, 'nodes_id', $node->{ nodes_id } );
            map { $graph->add_weighted_edge( $node->{ nodes_id }, $_->{ target_id }, 1 ) } @{ $node->{ links } };
        }
    }
    
    return $graph;
}

# run Graph::Layout::Aesthetic on the nodes and add the {x} and {y} fields to each node
sub plot_nodes
{
    my ( $method, $nodes ) = @_;

    my $graph = _add_nodes_and_links_to_graph( $nodes );

    $graph = _run_force_layout_on_graph( $graph, $nodes );
}

1;
