package MediaWords::Util::GraphLayoutAesthetic;

use strict;
use Data::Dumper;

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
    my ( $graph ) = @_;
    
    my $json_string = '[';
    
    for my $vertex ($graph->vertices)
    {   
        my $x = $graph->get_vertex_attribute($vertex, "x_coord");
        my $y = $graph->get_vertex_attribute($vertex, "y_coord");
        my $name = MediaWords::Util::HTML::javascript_escape( $graph->get_vertex_attribute($vertex, "name") );
        my $group = $graph->get_vertex_attribute($vertex, "group");
        
        $json_string .= "{ nodeName: '$name', x: $x, y: $y, group: $group },\n" if $group;
    }
    
    $json_string .= ']';
    
    return $json_string;
}

# Run the actual force layout

sub _run_force_layout_on_graph
{
    my ( $graph ) = @_;
    
    Graph::Layout::Aesthetic->gloss_graph( 
        $graph,
        pos_attribute => ["x_coord", "y_coord"],
        forces => {
            node_repulsion  => 1,
            min_edge_length => 1
        }
    );
    
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
            $graph->set_vertex_attribute($node->{ media_id }, 'name', $node->{ name });
            $graph->set_vertex_attribute($node->{ media_id }, 'group', $node->{ cluster_id });
        }
    }
    
    for my $node (@$nodes)
    {
        if ( defined $node->{ links } )
        {
            my $source_id = $node->{ media_id };
            for my $link ( @{ $node->{ links } } )
            {
                my $target_id = $link->{ target_id };
                my $value = ( $link->{ weight } );
                $graph->add_weighted_edge($source_id, $target_id, $value); # if $source_id < $target;
            }
        }
    }
    
    return $graph;
}

# Prepare the graph; run the force layout; get the appropriate JSON string from it.
sub get_graph
{
    my ( $nodes ) = @_;
    
    my $graph = _add_nodes_and_links_to_graph( $nodes );
    $graph = _run_force_layout_on_graph( $graph );
    
    my $json_string = _get_json_from_graph( $graph );

    return $json_string;
}

1;