package MediaWords::Cluster::Map::GraphLayoutAesthetic;

use strict;
use Data::Dumper;
use List::Member;
use Perl6::Say;

use Graph;
use Graph::Layout::Aesthetic;

sub _get_json_from_graph
{
    my ( $graph, $nodes, $centroids ) = @_;

    my $xMin;
    my $xMax;
    my $yMin;
    my $yMax;

    my $json_string = "{ ";

    $json_string .= "nodes: [";

    for my $vertex ( $graph->vertices )
    {
        next if ( !$graph->get_vertex_attribute( $vertex, "group" ) );
        
        my $x = $graph->get_vertex_attribute( $vertex, "x_coord" );
        my $y = $graph->get_vertex_attribute( $vertex, "y_coord" );

        $xMax = $x if ( !defined( $xMax ) || ( $x > $xMax ) );
        $xMin = $x if ( !defined( $xMin ) || ( $x < $xMin ) );
        $yMax = $y if ( !defined( $yMax ) || ( $y > $yMax ) );
        $yMin = $y if ( !defined( $yMin ) || ( $y < $yMin ) );
    }

    my $xRange = $xMax - $xMin;
    my $yRange = $yMax - $yMin;

    for my $vertex ( $graph->vertices )
    {
        my $x = $graph->get_vertex_attribute( $vertex, "x_coord" );
        my $norm_x = ( ( ( $x - $xMin ) / $xRange ) * 20 ) - 10;
        
        my $y = $graph->get_vertex_attribute( $vertex, "y_coord" );
        my $norm_y = ( ( ( $y - $yMin ) / $yRange ) * 20 ) - 10;

        my $name = MediaWords::Util::HTML::javascript_escape( $graph->get_vertex_attribute( $vertex, "name" ) );
        my $group = $graph->get_vertex_attribute( $vertex, "group" ) || 0;
        my $url = MediaWords::Util::HTML::javascript_escape( $graph->get_vertex_attribute( $vertex, "url" ) );
        
        $json_string .= "{ nodeID: $vertex, nodeName: '$name', x: $norm_x, y: $norm_y, raw_x: $x, raw_y: $y, group: $group, url: '$url' },\n"; 
    }
    $json_string .= "],\n";
    
    $json_string .= "clusters: [";
    for my $centroid ( @{ $centroids } )
    {
        my $id   = $centroid->{ id };
        my $name = $centroid->{ name };
        my $x    = $centroid->{ x };
        my $norm_x = ( ( ( $x - $xMin ) / $xRange ) * 20 ) - 10;

        my $y    = $centroid->{ y };
        my $norm_y = ( ( ( $y - $yMin ) / $yRange ) * 20 ) - 10;

        $json_string .= "{ name: '$name', id: $id, x: $norm_x, y: $norm_y },\n";
    }
    $json_string .= "],\n";

    $json_string .= "stats: {
            xMax: $xMax,
            xMin: $xMin,
            yMax: $yMax,
            yMin: $yMin
        },\n";
        
    $json_string .= "links: [";

    my $link_id = 0;
    for my $edge ( $graph->edges )
    {
        $json_string .= "[ $edge->[ 0 ], $edge->[ 1 ] ],\n";
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
    my ( $graph ) = @_;

    print STDERR "Glossing graph\n";

    Graph::Layout::Aesthetic->gloss_graph(
        $graph,
        pos_attribute => [ "x_coord", "y_coord" ],
        forces        => {
            node_repulsion  => 1,
            centripetal => 1,
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

    for my $i ( 0 .. $#{ $nodes } )
    {
        if ( my $node = $nodes->[ $i ] ) 
        {
            $graph->add_vertex( $i );
                
            $graph->set_vertex_attribute( $i, 'media_id',  $node->{ media_id } );
            $graph->set_vertex_attribute( $i, 'name',  $node->{ name } );
            $graph->set_vertex_attribute( $i, 'group', $node->{ cluster_id } );
            $graph->set_vertex_attribute( $i, 'url',   $node->{ url } );
        }
    }

    for my $j ( 0 .. $#{ $nodes } )
    {
        my $node = $nodes->[ $j ];

        if ( defined $node->{ links } )
        {
            for my $link ( @{ $node->{ links } } )
            {
                $graph->add_weighted_edge( $j, $link->{ target_id }, $link->{ weight } );
            }
        }
    }
    
    return $graph;
}

# Prepare the graph; run the force layout; get the appropriate JSON string from it.
sub get_graph
{
    my ( $nodes, $media_clusters ) = @_;

    my $json_string;
    
    eval {
        say STDERR "starting GraphLayoutAesthetic::get_graph";
        my $graph = _add_nodes_and_links_to_graph( $nodes );

        say STDERR "GraphLayoutAesthetic::get_graph running force layout on graph";
        $graph = _run_force_layout_on_graph( $graph );

        say STDERR "GraphLayoutAesthetic::get_graph running get_centroids_from_graph";
        my $centroids = _get_centroids_from_graph( $graph, $media_clusters, $nodes );

        say STDERR "GraphLayoutAesthetic::get_graph running _get_json_from_graph";
        $json_string = _get_json_from_graph( $graph, $nodes, $centroids );

        say STDERR "finishing GraphLayoutAesthetic::get_graph";
    };
    if ( $@ ) 
    {
        die( "error generating graph: '$@'" );
    }

    return $json_string;
}

1;
