package MediaWords::Cluster::Map::GraphViz;

use strict;
use Data::Dumper;
use List::Member;
use Perl6::Say;

use GraphViz;

use constant LAYOUT => 'neato';

# add nodes to graphviz graph object.
# add only the biggest N log(N) links at most to the graph where N = number of nodes;
# otherwise, the map gets squished together into a tight ball
sub _add_nodes_and_links_to_graph
{
    my ( $nodes ) = @_;

    my $graph = GraphViz->new( layout => LAYOUT, height => 20, width => 20 );
    my $links = [];

    for my $i ( 0 .. $#{ $nodes } )
    {
        if ( my $node = $nodes->[ $i ] ) 
        {
            $graph->add_node( $i );
            
            map { push( @{ $links }, [ $i, $_->{ target_id }, $_->{ sim } ] ) } @{ $node->{ links } };
        }
    }

    my $num_links = @{ $links };
    my $max_links = int( $num_links * log( $num_links ) );
    
    print STDERR "total links: $num_links\nmax links: $max_links\n";
        
    if ( $num_links > $max_links )
    {
        $links = [ sort { $b->[ 2 ] <=> $a->[ 2 ] } @{ $links } ];
        splice( @{ $links }, $max_links );
        $num_links = $max_links;
    }

    for my $link ( @{ $links } )
    {
        # graphviz doesn't pay attention to weights, but it does to lengths
        $graph->add_edge( $link->[ 0 ], => $link->[ 1 ], len => ( 1 - $link->[ 2 ] ) + 0.1 );
    }
    
    return ( $graph, $num_links );
}

# run the force layout and parse the text results from GraphViz.
# add {x} and {y} fields to each node.
# 
# the output to parse from $graph->as_text looks like:
# digraph test {
#   graph [ratio=fill];
#   node [label="\N"];
#   graph [bb="0,0,126,108"];
#   node1 [label=0, pos="99,90", width="0.75", height="0.50"];
#   node2 [label=1, pos="27,18", width="0.75", height="0.50"];
#   node3 [label=2, pos="99,18", width="0.75", height="0.50"];
#   node1 -> node2 [weight=1, pos="e,42,33 84,75 74,65 61,52 49,40"];
#   node1 -> node3 [weight=2, pos="e,99,36 99,72 99,64 99,55 99,46"];
# }
sub _run_force_layout
{
    my ( $graph, $nodes ) = @_;
    
    my $output = $graph->as_text;
    
    while ( $output =~ /label=(\d+), pos="(\d+),(\d+)"/g )
    {
        my ( $node_id, $x, $y ) = ( $1, $2, $3 );
        
        $nodes->[ $node_id ]->{ x } = $x;
        $nodes->[ $node_id ]->{ y } = $y;
    }
}

# Prepare the graph; run the force layout; get the appropriate JSON string from it.
sub get_graph
{
    my ( $nodes, $media_clusters, $media_sets ) = @_;
    
    my ( $graph, $num_links_rendered ) = _add_nodes_and_links_to_graph( $nodes );

    _run_force_layout( $graph, $nodes );
    
    return $num_links_rendered;
}

1;
