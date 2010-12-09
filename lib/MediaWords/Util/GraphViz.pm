package MediaWords::Util::GraphViz;

use strict;
use Data::Dumper;
#use GraphViz;
use File::Util;

sub _get_json_from_graph
{
    my ( $graph, $nodes ) = @_;

    my $json_string = "[";

    my @graphviz_output = split( "\n", $graph->as_text );
    for my $line ( @graphviz_output )
    {
        if ( $line =~ /^ \s* node(\d+) \s* \[label= "? (.+) "? , \s .* pos="(\d+),(\d+)" .* $/ix )
        {
            print STDERR "$line\n";
            my $node  = $nodes->[ $1 ];
            my $name  = MediaWords::Util::HTML::javascript_escape $node->{ name };
            my $group = $node->{ cluster_id };
            my $x     = $3;
            my $y     = $4;
            $json_string .= "{ nodeName: '$name', x: $x, y: $y, group: $group },\n" if $group;
        }
    }

    $json_string .= "]";

    print STDERR "$json_string\n";

    return $json_string;
}

sub _write_graph_to_file
{
    my ( $graph ) = @_;

    my $content = $graph->as_png();

    my $f = File::Util->new();
    $f->write_file( 'file' => '/tmp/graphviz.png', 'content' => $content );
}

sub _add_nodes_and_links_to_graph
{
    my ( $nodes ) = @_;

    my $graph = GraphViz->new(
        directed => 0,
        layout   => 'fdp'
    );

    my $node_id_count = 0;    # intialize count of node_ids

    for my $node ( @$nodes )
    {
        if ( $node->{ linked } )
        {
            my $label   = MediaWords::Util::HTML::javascript_escape $node->{ name };
            my $id      = $node_id_count++;
            my $cluster = $node->{ cluster_id };
            $node->{ node_id } = $id;

            $graph->add_node( $id, label => $label, cluster => $cluster );
        }
    }

    for my $node ( @$nodes )
    {
        if ( defined $node->{ links } )
        {
            my $source_id = $node->{ node_id };
            for my $link ( @{ $node->{ links } } )
            {
                my $target_id = $nodes->[ $link->{ target_id } ]->{ node_id };
                my $weight    = ( $link->{ weight } );

                $graph->add_edge( $source_id => $target_id, weight => $weight );
            }
        }
    }

    return $graph;
}

sub get_graph
{
    my ( $nodes ) = @_;

    my $graph = _add_nodes_and_links_to_graph( $nodes );

    # _write_graph_to_file( $graph );

    my $json_string = _get_json_from_graph( $graph, $nodes );

    return $json_string;
}

1;
