package MediaWords::Controller::Clusters;

# set of screens for listing, creating, and viewing the results of clustering runs

use strict;
use warnings;
use parent 'Catalyst::Controller';

use MediaWords::Cluster;
use MediaWords::Util::Tags;
use Data::Dumper;

# Set a threshold for link weight--links won't be displayed if they're less than this
# This reduces the number of links substantially, making it easier for the client to render
# It also improves the visualization by reducing a lot of noise
use constant MIN_LINK_WEIGHT => 0.2;

sub index : Path : Args(0)
{
    return list( @_ );
}

# list existing cluster runs
sub list : Local
{
    my ( $self, $c ) = @_;

    my $cluster_runs =
      $c->dbis->query( "select mcr.*, ms.name as media_set_name from media_cluster_runs mcr, media_sets ms " .
          "  where mcr.media_sets_id = ms.media_sets_id " . "  order by mcr.media_cluster_runs_id" )->hashes;

    $c->stash->{ cluster_runs } = $cluster_runs;

    $c->stash->{ template } = 'clusters/list.tt2';
}

# create a new cluster run, including both creating the media_cluster_runs entry and doing the cluster run
sub create : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/cluster.yml',
            method           => 'post',
            action           => $c->uri_for( '/clusters/create' ),
        }
    );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'clusters/create.tt2';
        return;
    }

    my $cluster_run =
      $c->dbis->create_from_request( 'media_cluster_runs', $c->request,
        [ qw/start_date end_date media_sets_id description num_clusters/ ] );

    MediaWords::Cluster::execute_and_store_media_cluster_run( $c->dbis, $cluster_run );

    $c->response->redirect( $c->uri_for( '/clusters/view/' . $cluster_run->{ media_cluster_runs_id } ) );
}

# view the results of a cluster run
sub view : Local
{
    my ( $self, $c, $cluster_runs_id ) = @_;

    my $run = $c->dbis->find_by_id( 'media_cluster_runs', $cluster_runs_id ) || die( "Unable to find run $cluster_runs_id" );

    my $media_clusters =
      $c->dbis->query( "select * from media_clusters where media_cluster_runs_id = ?", $cluster_runs_id )->hashes;

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
    
    my $nodes = [];  
    $nodes->[0] = {}; # initialize the first node -- must be a hash ref!
    
    for my $mc ( @{ $media_clusters } )
    {   
        # store the cluster_id
        my $cluster_id = $mc->{ media_clusters_id };
        
        my $mc_media = $c->dbis->query(
            "select distinct m.*, mcz.* from media m, media_clusters_media_map mcmm, media_cluster_zscores mcz 
                 where m.media_id = mcmm.media_id
                   and m.media_id = mcz.media_id
                   and mcmm.media_clusters_id = mcz.media_clusters_id
                   and mcmm.media_clusters_id = ?",
            $mc->{ media_clusters_id }
        )->hashes;
        $mc->{ media } = $mc_media;
        
        # for each source, add its info to the nodes array
        for my $source (@{ $mc_media }) {
            my $mid  = $source->{ media_id };
            $nodes->[$mid] = {
                name                => $source->{ name },
                cluster_id          => $cluster_id,
                media_id            => $mid,
                internal_zscore     => $source->{ internal_zscore },
                internal_similarity => $source->{ internal_similarity },
                external_zscore     => $source->{ external_zscore },
                external_similarity => $source->{ external_similarity },
                word_count          => 0, #$source->{ total_count },
                linked              => 0
            };
        }
        
        $mc->{ internal_features } = $c->dbis->query(
            "select * from media_cluster_words " . "  where media_clusters_id = ? and internal = 't' " .
              "  order by weight desc limit 50",
            $mc->{ media_clusters_id }
        )->hashes;
        
        $mc->{ external_features } = $c->dbis->query(
            "select * from media_cluster_words " . "  where media_clusters_id = ? and internal = 'f' " .
              "  order by weight desc limit 50",
            $mc->{ media_clusters_id }
        )->hashes;
        
    }

    $run->{ tag_name } = MediaWords::Util::Tags::lookup_tag_name( $c->dbis, $run->{ tags_id } );    
    
    $nodes = _add_links_to_nodes($c, $cluster_runs_id, $nodes);
    # $nodes = _add_links_from_zscores($nodes); # Alternative method to add links
    
    # print STDERR "\$nodes: " . Dumper($nodes);

    $c->stash->{ media_clusters } = $media_clusters;
    $c->stash->{ run }            = $run;
    $c->stash->{ template }       = 'clusters/view.tt2';
    $c->stash->{ data }           = _get_json_object_from_nodes($nodes);
}

sub _my_escape
{
    use MediaWords::Util::HTML;
    
    my ($s) = @_;
    
    $s = MediaWords::Util::HTML::html_strip($s);
    
    $s =~ s/'/\\'/g;
    
    return $s;
}

sub _get_json_object_from_nodes
{
    my ($nodes) = @_;
    
    my $data = "{ nodes:[";   # prep JSON object as string
    
    # add nodes to data string
    my $node_id_count = 0;   # intialize count of node_ids
    for my $node (@$nodes) {
        # Don't render orphan nodes--i.e. those that don't have any links > MIN_LINK_WEIGHT
        if ( $node->{ linked } ) {
            my $node_name      = _my_escape( $node->{ name } );
            my $group          = $node->{ cluster_id };
            my $size           = ($node->{ word_count }) ** (0.5) * 3;
            $node->{ node_id } = $node_id_count++;
            $data .= "{ nodeName:'$node_name', group:$group, size:$size },\n";
        }
    }
    
    $data .= ' ], links:[';   # close nodes section, start links
    
    # add links to data string
    for my $node (@$nodes) {
        if ( defined $node->{ links } ) {
            my $source_id = $node->{ node_id };
            for my $link (@{ $node->{ links } }) {
                my $target = $nodes->[ $link->{ target_id } ]->{ node_id };
                my $value = ($link->{ weight }); 
                $data .= "{ source:$source_id, target:$target, value:$value },\n"; # if $source_id < $target;
            }
        }
    }
    
    $data .= '] }';     # write end of data string
    
    # print STDERR "\$data: $data\n\n";
    
    return $data;
}

# Old way of computing links: based on internal/external z-scores/similarities from cluto
sub _add_links_from_zscores
{
    my ($nodes) = @_;
    
    use constant WEIGHT_SCALE => 2;
    
    for my $node (@{ $nodes }) {
    
        my $node_id = $node->{ media_id } or next;   # store away node id
        my $cluster_id = $node->{ cluster_id };
        
        ## use 2 ^ whatever to avoid negatives....
        my $ext_zscore = WEIGHT_SCALE ** $node->{ external_zscore };        # store the node's external weight
        my $ext_sim    = WEIGHT_SCALE ** $node->{ external_similarity };    # store the node's external similarity
        my $ext_weight = $ext_zscore > 100 ? $ext_sim : $ext_sim / 50 + $ext_zscore;  # sanity check
        
        my $int_zscore = WEIGHT_SCALE ** $node->{ internal_zscore };        # store the node's internal weight
        my $int_sim    = WEIGHT_SCALE ** $node->{ internal_similarity };    # store the node's internal similarity
    
        for my $sibling (@{ $nodes }) {            # find connections to other nodes        
            my $target_id = $sibling->{ media_id } or next;
                      
            if ($target_id > 0 && $target_id != $node_id) { # only real ones!

                if ( $sibling->{ cluster_id } == $cluster_id) { # find the sibling nodes
                    my $target_int_weight = WEIGHT_SCALE ** $sibling->{ internal_zscore };
                    my $int_weight        = $int_sim + $int_zscore + $target_int_weight;
                    if ($int_weight > 4) {
                        push(@{ $node->{ links } }, { target_id => $target_id, weight => ($int_weight) } );
                        $node->{ linked } = 1;
                        $sibling->{ linked } = 1;
                    }
                }
                elsif (1) { # Draw links across clusters?
                    my $target_ext_zscore = WEIGHT_SCALE ** $sibling->{ external_zscore };
                    my $target_ext_sim    = WEIGHT_SCALE ** $node->{ external_similarity };    # store the node's external similarity
                    my $target_ext_weight = $target_ext_zscore > 500 ?
                            $target_ext_sim / 50 : $target_ext_sim + $target_ext_zscore;
                    my $weight = ($ext_weight + $target_ext_weight);
                    if ($weight > 12) {
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
    my ($c, $cluster_runs_id, $nodes) = @_;
   
    my $links = $c->dbis->query(
        "select distinct mcl.source_media_id, mcl.target_media_id, mcl.weight
           from media_cluster_links mcl
          where mcl.media_cluster_runs_id = ?", $cluster_runs_id
    )->hashes;
    
    my $linked_nodes = []; # a boolean array--true for every $mid with a node
    
    for my $link (@{ $links }) {
        my ($weight, $target, $source) = values %{ $link };
        if ( $weight > MIN_LINK_WEIGHT ) {
            push( @{ $nodes->[ $source ]->{ links } }, {
                    target_id => $target,
                    weight    => $weight * 10 # make node weight [0,10] not [0,1]
                }
            );
            $nodes->[ $source ]->{ linked } = 1;
            $nodes->[ $target ]->{ linked } = 1;
        }
    }
    
    # print STDERR "\n\nLINKS: " . Dumper($links) . "\n\n";
    
    return $nodes;
}

1;
