package MediaWords::Util::Protovis;

# All of the controller code to get media sources ready for Protivis.

use strict;
use MediaWords::Util::HTML;
use Math::Random;
use Data::Dumper;

use constant MIN_LINK_WEIGHT => 0.2;
use constant MAX_NUM_LINKS => 10000;

# $nodes should ultimately look like this: 
# $nodes = [
#     media_id1 => {
#         name                => "name",
#         cluster_id          => $cluster_id,
#         media_id            => $media_id,
#         internal_zscore     => $int_zscore,
#         internal_similarity => $int_sim,
#         external_zscore     => $ext_zscore,
#         external_similarity => $ext_sim,
#         linked              => false
#         links => [
#             {
#                 target_id => $target_1_id
#                 weight    => $link_1_weight
#             },
#             ...
#         ]
#         word_count          => $total_count
#         node_id             => $node_id
#     },
#     ...
# ]

# Systematically cut down links... just arbitarily get rid of a lot of them in the bottom half
sub _trim_links
{
    my ( $links, $num_top_links, $num_random_links ) = @_;

    # shouldn't be necessary--links should be sorted when you get them back from the DB
    # my @sorted_links = sort { $a->{ weight } <=> $b->{ weight } } @{ $links };

    my $new_links = [];
    @{ $new_links } = @$links[ 0 .. $num_top_links - 1 ];

    # for my $num ( Math::Random::random_uniform_integer( $max_links - ( @$links / 2 ), @$links / 2, $#{ $links } ) )
    for my $num ( Math::Random::random_uniform_integer( $num_random_links, $num_top_links, $#{ $links } ) )
    {
        push @{ $new_links }, $links->[$num];
    }

    return $new_links;
}

# Trim down the number of links that each node has
# Display the $num_top_links strongest links, and $num_random_links other random links from each node
sub _limit_links_per_node
{
    my ( $nodes, $num_top_links, $num_random_links ) = @_;
    
    for my $node ( @{ $nodes } )
    {
        if ( defined $node->{ links } and scalar @{ $node->{ links } } > $num_top_links + $num_random_links )
        {
            my @sorted_links = sort { $a->{ weight } <=> $b->{ weight } } @{ $node->{ links } };      
            
            my $new_links = [];
            @{ $new_links } = @sorted_links[ 0 .. $num_top_links - 1 ];
            
            for my $num ( Math::Random::random_uniform_integer( $num_random_links, $num_top_links, $#sorted_links ) )
            {
                push @{ $new_links }, $sorted_links[$num];
            }
            
            $node->{ links } = $new_links;
        }
    }
    
    return $nodes;
}

# Return a hash ref with the number of links and nodes
sub _update_stats
{
    my ( $nodes ) = @_;
    my $num_nodes_total = 0;
    my $num_nodes_rendered = 0;
    my $num_links = 0;
    
    for my $node ( @{ $nodes } )
    {
        $num_nodes_total++ if defined $node->{ media_id };
        $num_links += scalar @{ $node->{ links } } if defined $node->{ links };
        $num_nodes_rendered++ if $node->{ linked };    
    }
    
    my $stats = {
        num_nodes_total     => $num_nodes_total,
        num_nodes_rendered  => $num_nodes_rendered,
        num_links           => $num_links
    };
    
    return $stats;
}

# Old way of computing links: based on internal/external z-scores/similarities from cluto
sub _add_links_from_zscores
{
    my ($nodes) = @_;
    
    use constant WEIGHT_SCALE => 2;
    
    for my $node (@{ $nodes })
    {
        my $node_id = $node->{ media_id } or next;   # store away node id
        my $cluster_id = $node->{ cluster_id };
        
        ## use 2 ^ whatever to avoid negatives....
        my $ext_zscore = WEIGHT_SCALE ** $node->{ external_zscore };        # store the node's external weight
        my $ext_sim    = WEIGHT_SCALE ** $node->{ external_similarity };    # store the node's external similarity
        my $ext_weight = $ext_zscore > 100 ? $ext_sim : $ext_sim / 50 + $ext_zscore;  # sanity check
        
        my $int_zscore = WEIGHT_SCALE ** $node->{ internal_zscore };        # store the node's internal weight
        my $int_sim    = WEIGHT_SCALE ** $node->{ internal_similarity };    # store the node's internal similarity
    
       # find connections to other nodes 
        for my $sibling (@{ $nodes }) 
        {                  
            my $target_id = $sibling->{ media_id } or next;
                      
            if ( $target_id > 0 && $target_id != $node_id )  # only real ones!
            { 
                if ( $sibling->{ cluster_id } == $cluster_id)
                { # find the sibling nodes
                    my $target_int_weight = WEIGHT_SCALE ** $sibling->{ internal_zscore };
                    my $int_weight        = $int_sim + $int_zscore + $target_int_weight;
                    if ($int_weight > 4)
                    {
                        push(@{ $node->{ links } }, { target_id => $target_id, weight => ($int_weight) } );
                        $node->{ linked } = 1;
                        $sibling->{ linked } = 1;
                    }
                }
                elsif (1) # Draw links across clusters?
                { 
                    my $target_ext_zscore = WEIGHT_SCALE ** $sibling->{ external_zscore };
                    my $target_ext_sim    = WEIGHT_SCALE ** $node->{ external_similarity };    # store the node's external similarity
                    my $target_ext_weight = $target_ext_zscore > 500 ?
                            $target_ext_sim / 50 : $target_ext_sim + $target_ext_zscore;
                    my $weight = ($ext_weight + $target_ext_weight);
                    
                    if ($weight > 12)
                    {
                        push(@{ $node->{ links } }, { target_id => $target_id, weight => $weight/2 } );
                        $node->{ linked } = 1;
                        $sibling->{ linked } = 1;
                    }
                }
            }
        }
        
        # print STDERR "\n\n LINKS: " . Dumper($node->{ links }) . "\n\n";
    }
    
    return $nodes;
}

# Query media_cluster_links and add links to each node
sub _add_links_to_nodes
{
    my ( $c, $cluster_runs_id, $nodes ) = @_;
   
    my $links = $c->dbis->query(
        "select distinct mcl.source_media_id, mcl.target_media_id, mcl.weight
           from media_cluster_links mcl
          where mcl.media_cluster_runs_id = ?
            and mcl.weight > ?
       order by mcl.weight desc
          limit ?", $cluster_runs_id, MIN_LINK_WEIGHT, MAX_NUM_LINKS
    )->hashes;
    
    # $links = _trim_links( $links, 0, 10000 );
    
    for my $link ( @{ $links } )
    {
        my ($weight, $target, $source) = values %{ $link };
        push @{ $nodes->[ $source ]->{ links } }, {
            target_id => $target,
            weight    => $weight * 10 # make node weight [0,10] not [0,1]
        };
        $nodes->[ $source ]->{ linked } = 1;
        $nodes->[ $target ]->{ linked } = 1;
    }
    
    # print STDERR "\n\nLINKS: " . Dumper($links) . "\n\n";
    
    return $nodes;
}

# Turn the nodes object into a JSON object for Protovis' force layout
sub _get_protovis_json_object
{
    my ( $nodes ) = @_;
    
    my $data = "{ nodes:[";  # start nodes section
    my $node_id_count = 0;   # intialize count of node_ids
    
    for my $node ( @{ $nodes } )
    {
        # Don't render orphan nodes--i.e. those that don't have any links > MIN_LINK_WEIGHT
        if ( $node->{ linked } )
        {
            my $node_name      = MediaWords::Util::HTML::javascript_escape( $node->{ name } );
            my $group          = $node->{ cluster_id };
            my $size           = ($node->{ word_count }) ** (0.5) * 3;
            $node->{ node_id } = $node_id_count++;
            $data .= "{ nodeName:'$node_name', group:$group, size:$size },\n";
        }
    }
    
    $data .= ' ], links:['; # close nodes section, start links section
    
    # add links to data string
    for my $node (@$nodes)
    {
        if ( defined $node->{ links } )
        {
            my $source_id = $node->{ node_id };
            for my $link ( @{ $node->{ links } } )
            {
                my $target = $nodes->[ $link->{ target_id } ]->{ node_id };
                my $value = ( $link->{ weight } ); 
                $data .= "{ source:$source_id, target:$target, value:$value },\n"; # if $source_id < $target;
            }
        }
    }
    
    $data .= '] }'; # write end of data string
    
    return $data;
}

# add the basic info about every node
sub _initialize_nodes_from_media_list
{
    my ( $media_clusters ) = @_;
    
    my $nodes = [];
    $nodes->[0] = {}; # initialize the first node -- must be a hash ref!
    
    for my $mc ( @{ $media_clusters } )
    {
        my $cluster_id = $mc->{ media_clusters_id };
        
        # for each source, add its info to the nodes array
        for my $source ( @{ $mc->{ media } } )
        {
            my $mid = $source->{ media_id };
            $nodes->[$mid] = {
                name                => $source->{ name },
                cluster_id          => $cluster_id,
                media_id            => $mid,
                internal_zscore     => $source->{ internal_zscore },
                internal_similarity => $source->{ internal_similarity },
                external_zscore     => $source->{ external_zscore },
                external_similarity => $source->{ external_similarity },
                word_count          => 0, #source->{ total_count },
                linked              => 0
            };
        }
    }
    
    return $nodes;
}

# Set up the 'nodes' data structure with links, and return the JSON object and stats
sub prep_nodes_for_protovis
{
    my ( $media_clusters, $c, $cluster_runs_id, $nodes ) = @_;
    
    $nodes = _initialize_nodes_from_media_list( $media_clusters );
    
    $nodes = _add_links_to_nodes($c, $cluster_runs_id, $nodes);
    # $nodes = _add_links_from_zscores($nodes); # Alternative method to add links
    
    # $nodes = _limit_links_per_node($nodes, 0, 20);
    
    my $protovis_json = _get_protovis_json_object($nodes);
    my $stats = _update_stats($nodes);
    
    return ( $protovis_json, $stats );
}

1;