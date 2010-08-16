package MediaWords::Util::GraphLayoutAesthetic;

use strict;
use Data::Dumper;
use List::Member;

use Graph;
use Graph::Layout::Aesthetic;

# Prints the coordinates of every point in the graph
sub _dump_graph
{
    my ( $graph ) = @_;
    print STDERR Dumper( $graph );
}

sub _get_json_from_graph
{
    my ( $graph, $nodes, $centroids ) = @_;

    my $xMin = 0;
    my $xMax = 0;
    my $yMin = 0;
    my $yMax = 0;

    my $json_string = "{    clusters: [";

    for my $centroid ( @$centroids )
    {
        my $id   = $centroid->{ id };
        my $name = $centroid->{ name };
        my $x    = $centroid->{ x };
        my $y    = $centroid->{ y };

        $json_string .= "{ name: '$name', id: $id, x: $x, y: $y },\n";
    }

    $json_string .= "],\n     nodes: [";

    for my $vertex ( $graph->vertices )
    {
        my $x = $graph->get_vertex_attribute( $vertex, "x_coord" );
        my $y = $graph->get_vertex_attribute( $vertex, "y_coord" );
        my $name = MediaWords::Util::HTML::javascript_escape( $graph->get_vertex_attribute( $vertex, "name" ) );
        my $group = $graph->get_vertex_attribute( $vertex, "group" );
        my $url = MediaWords::Util::HTML::javascript_escape( $graph->get_vertex_attribute( $vertex, "url" ) );

        $xMax = $x if ( $x > $xMax );
        $xMin = $x if ( $x < $xMin );
        $yMax = $y if ( $y > $yMax );
        $yMin = $y if ( $y < $yMin );

        $json_string .= "{ nodeID: $vertex, nodeName: '$name', x: $x, y: $y, group: $group, url: '$url' },\n" if $group;
    }

    $json_string .= "],
        stats: {
            xMax: $xMax,
            xMin: $xMin,
            yMax: $yMax,
            yMin: $yMin
        },\n    links: [";

    my $link_id = 0;
    for my $edge ( $graph->edges )
    {
        my $node_1 = $nodes->[ $edge->[ 0 ] ]->{ node_id };
        my $node_2 = $nodes->[ $edge->[ 1 ] ]->{ node_id };

        $json_string .= "[ $node_1, $node_2 ],\n";
    }

    $json_string .= '] }';

    return $json_string;
}

sub _get_centroids_from_graph
{
    my ( $graph, $media_clusters, $nodes ) = @_;

    my $centroids = [];

    for my $cluster ( @{ $media_clusters } )
    {
        # TODO: Refactor this into separate subroutine (requires that your clustering scheme calculates and your
        #    database stores the cluster's centroid)
        # Cluster centroid approach
        #
        # my $centroid_id = $cluster->{ centroid_id };
        #
        # my $centroid = {
        #     centroid_id => $centroid_id,
        #     x => $graph->get_vertex_attribute($centroid_id, "x_coord"),
        #     y => $graph->get_vertex_attribute($centroid_id, "y_coord"),
        #     id => $cluster->{ media_clusters_id },
        #     name => $cluster->{ description }
        # };
        #
        # push @{ $centroids }, $centroid if ( $centroid->{ x } and $centroid->{ y } );

        ##########################################################################################
        # weighted average approach

        my $cluster_id   = $cluster->{ media_clusters_id };
        my $cluster_name = $cluster->{ description };

        my $xTotal = 0;
        my $yTotal = 0;

        my $num_nodes = 0;

        for my $node ( @{ $cluster->{ media } } )
        {
            my $media_id = $node->{ media_id };

            my $xCoord = $graph->get_vertex_attribute( $media_id, "x_coord" );
            my $yCoord = $graph->get_vertex_attribute( $media_id, "y_coord" );

            if ( defined $xCoord and defined $yCoord )
            {
                $xTotal += $xCoord;
                $yTotal += $yCoord;
                $num_nodes++;
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
    my ( $graph ) = @_;

    print STDERR "Glossing graph\n";

    Graph::Layout::Aesthetic->gloss_graph(
        $graph,
        pos_attribute => [ "x_coord", "y_coord" ],
        forces        => {
            node_repulsion  => 1,
            min_edge_length => 1
        }
    );

    print STDERR "Done glossing graph\n";

    return $graph;
}

# Prepare the graph by adding nodes and links to it
sub _add_nodes_and_links_to_graph
{
    my ( $nodes ) = @_;

    my $graph = Graph::Undirected->new;

    my $node_id_count = 0;

    for my $node ( @{ $nodes } )
    {

        # Don't render orphan nodes--i.e. those that don't have any links > MIN_LINK_WEIGHT
        if ( $node->{ linked } )
        {
            $node->{ node_id } = $node_id_count++;
            $graph->add_vertex( $node->{ media_id } );
            $graph->set_vertex_attribute( $node->{ media_id }, 'name',  $node->{ name } );
            $graph->set_vertex_attribute( $node->{ media_id }, 'group', $node->{ cluster_id } );
            $graph->set_vertex_attribute( $node->{ media_id }, 'url',   $node->{ url } );
        }
    }

    for my $node ( @$nodes )
    {
        if ( defined $node->{ links } )
        {
            my $source_id = $node->{ media_id };
            for my $link ( @{ $node->{ links } } )
            {
                my $target_id = $link->{ target_id };
                my $value     = ( $link->{ weight } );
                $graph->add_weighted_edge( $source_id, $target_id, $value );    # if $source_id < $target;
            }
        }
    }

    return $graph;
}

# Prepare the graph; run the force layout; get the appropriate JSON string from it.
sub get_graph
{
    my ( $nodes, $media_clusters ) = @_;

    my $graph = _add_nodes_and_links_to_graph( $nodes );
    $graph = _run_force_layout_on_graph( $graph );

    my $centroids = _get_centroids_from_graph( $graph, $media_clusters, $nodes );

    my $json_string = _get_json_from_graph( $graph, $nodes, $centroids );

    return $json_string;
}

1;
