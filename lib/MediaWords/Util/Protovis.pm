package MediaWords::Util::Protovis;

# All of the controller code to get media sources ready for Protivis.

use strict;
use MediaWords::Util::HTML;

# Turn the nodes object into a JSON object for Protovis' force layout
sub get_protovis_force_json_object
{
    my ( $nodes ) = @_;

    my $data          = "{ nodes:[";    # start nodes section
    my $node_id_count = 0;              # intialize count of node_ids

    for my $node ( @{ $nodes } )
    {

        # Don't render orphan nodes--i.e. those that don't have any links > MIN_LINK_WEIGHT
        if ( $node->{ linked } )
        {
            my $node_name = MediaWords::Util::HTML::javascript_escape( $node->{ name } );
            my $group     = $node->{ cluster_id };
            my $size      = ( $node->{ word_count } )**( 0.5 ) * 3;
            $node->{ node_id } = $node_id_count++;
            $data .= "{ nodeName:'$node_name', group:$group, size:$size },\n";
        }
    }

    $data .= ' ], links:[';    # close nodes section, start links section

    # add links to data string
    for my $node ( @$nodes )
    {
        if ( defined $node->{ links } )
        {
            my $source_id = $node->{ node_id };
            for my $link ( @{ $node->{ links } } )
            {
                my $target = $nodes->[ $link->{ target_id } ]->{ node_id };
                my $value  = ( $link->{ weight } );
                $data .= "{ source:$source_id, target:$target, value:$value },\n";    # if $source_id < $target;
            }
        }
    }

    $data .= '] }';                                                                   # write end of data string

    return $data;
}

1;
