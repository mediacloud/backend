package MediaWords::Util::GraphLayoutAesthetic;

use strict;
use Data::Dumper;
use Graph;
use Graph::Layout::Aesthetic;
use MediaWords::Util::GraphPrep;

# Prints the coordinates of every point in the aglo
sub _dump_graph
{
    my ( $aglo ) = @_;
    
    my $i = 0;
    for my $coordinate ($aglo->all_coordinates)
    {
        print STDERR "Vertex ", $i++, ": ", Dumper($coordinate), "\n";
    }
}

# Get info about the number of nodes and links rendered
sub _get_stats_from_aglo
{
    my ( $aglo ) = @_;
    
    my $stats = {
        num_nodes_total     => "unknown",
        num_nodes_rendered  => scalar @{ $aglo->all_coordinates },
        num_links           => scalar @{ $aglo->increasing_edges }
    };
    
    return $stats;
}

sub _get_json_from_graph
{
    my ( $graph ) = @_;
    
    my $json_string = '[';
    
    for my $vertex ($graph->vertices)
    {   
        print STDERR Dumper($vertex);
        my $x = $graph->get_vertex_attribute($vertex, "x_coord");
        my $y = $graph->get_vertex_attribute($vertex, "y_coord");
        my $name = MediaWords::Util::HTML::javascript_escape( $graph->get_vertex_attribute($vertex, "name") );
        my $group = $graph->get_vertex_attribute($vertex, "group");
        $json_string .= "{ nodeName: '$name', x: $x, y: $y, group: $group },\n" if $group;
    }
    
    $json_string .= ']';
    
    print STDERR "$json_string\n\n";
    
    return $json_string;
}

sub _set_up_graph
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

sub get_node_positions
{
    my ( $nodes ) = MediaWords::Util::GraphPrep::get_nodes( @_ );
    
    my $graph = _set_up_graph( $nodes );
    
    my $json_string = _get_json_from_graph( $graph );
    
    my $stats = MediaWords::Util::GraphPrep::update_stats( $nodes );
    
    return ($json_string, $stats);
}

1;