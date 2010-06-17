package MediaWords::Controller::Clusters;

# set of screens for listing, creating, and viewing the results of clustering runs

use strict;
use warnings;
use parent 'Catalyst::Controller';

use MediaWords::Cluster;
use MediaWords::Util::Tags;
use Data::Dumper;

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

   
    my @nodes = [];           # create an array of node hashes
    $nodes[0] = {};           # initialize the first node -- must be a hash ref!
    # $nodes[0]->{ name }       = $run->{ description };
    # $nodes[0]->{ node_id }    = 0;
    # $nodes[0]->{ cluster_id } = 0;
    # $nodes[0]->{ media_id }   = 0;
    # $nodes[0]->{ links }      = [{}];
    
    
    my @clusters = [];       # store away the info about clusters...
    
    for my $mc ( @{ $media_clusters } )
    {   
        # store the cluster_id
        my $cluster_id = $mc->{ media_clusters_id };
        
        my $mc_media = $c->dbis->query(
            "select m.*, mcz.* from media m, media_clusters_media_map mcmm, media_cluster_zscores mcz" .
              "  where m.media_id = mcmm.media_id
                   and m.media_id = mcz.media_id 
                   and mcmm.media_clusters_id = mcz.media_clusters_id
                   and mcmm.media_clusters_id = ?",
            $mc->{ media_clusters_id }
        )->hashes;
        $mc->{ media } = $mc_media;
        
        ######### DO NOT Make the cluster center a node ###############
        # $nodes[$node_id_count] = {};
        # $nodes[$node_id_count]->{ name }       = $mc->{ description } . " ($cluster_id)";
        # $nodes[$node_id_count]->{ node_id }    = $node_id_count;
        # $nodes[$node_id_count]->{ cluster_id } = $cluster_id;
        # $nodes[$node_id_count]->{ media_id }   = 0;
        # $nodes[$node_id_count]->{ links }      = [{}];
        # $node_id_count++;
        
        # for each source, add its info to the JSON object
        for my $source (@{ $mc_media }) {
            my $mid  = $source->{ media_id };
            $nodes[$mid] = {};
            $nodes[$mid]->{ name }       = $source->{ name };
            $nodes[$mid]->{ cluster_id } = $cluster_id;
            $nodes[$mid]->{ media_id }   = $mid;
            $nodes[$mid]->{ links }      = [];
            $nodes[$mid]->{ internal_zscore } = $source->{ internal_zscore };
            $nodes[$mid]->{ internal_similarity } = $source->{ internal_similarity };
            $nodes[$mid]->{ external_zscore } = $source->{ external_zscore };
            $nodes[$mid]->{ external_similarity } = $source->{ external_similarity };
        }
        
        $mc->{ internal_features } = $c->dbis->query(
            "select * from media_cluster_words " . "  where media_clusters_id = ? and internal = 't' " .
              "  order by weight desc",
            $mc->{ media_clusters_id }
        )->hashes;
        
        $mc->{ external_features } = $c->dbis->query(
            "select * from media_cluster_words " . "  where media_clusters_id = ? and internal = 'f' " .
              "  order by weight desc",
            $mc->{ media_clusters_id }
        )->hashes;
        
    }

    $run->{ tag_name } = MediaWords::Util::Tags::lookup_tag_name( $c->dbis, $run->{ tags_id } );    
    
    ############# Add links from cluster_links table ########################
   
    my $links = $c->dbis->query(
        "select mcl.* from media_cluster_links mcl where mcl.media_cluster_runs_id = ?", $cluster_runs_id
    )->hashes;
    
    for my $link (@{ $links }) {   
        push( @{ $nodes[ $link->{ source_media_id } ]->{ links } }, {
                target_id => $link->{ target_media_id },
                weight    => $link->{ weight }
            }
        );
    }
    
    print STDERR "\n\nLINKS: " . Dumper($links) . "\n\n";
    
    ################ OLD WAY: links based on Cluto Z-scores ############################
    # for my $node (@nodes) {
    # 
    #     my $node_id = $node->{ node_id }; # store away node id
    #     # if ($node_id == 0 ) { next; }     # skip to the next thing if using a center node
    #     
    #     my $cluster_id = $node->{ cluster_id };
    #     
    #     ## use 10 ^ whatever to avoid negatives....
    #     my $ext_zscore = 2 ** $node->{ external_zscore };        # store the node's external weight
    #     my $ext_sim    = 2 ** $node->{ external_similarity };    # store the node's external similarity
    #     my $ext_weight = $ext_zscore > 100 ? $ext_sim : $ext_sim + $ext_zscore;  # sanity check
    #     
    #     
    #     my $int_zscore = 100 ** $node->{ internal_zscore };        # store the node's internal weight
    #     my $int_sim    = 100 ** $node->{ internal_similarity };    # store the node's internal similarity
    # 
    #     for my $sibling (@nodes) {            # find connections to other nodes              
    #         if ($sibling->{ media_id } > 0 && $sibling->{ node_id } != $node_id) { # only real ones!
    #             
    #             my $target_id = $sibling->{ node_id };
    #             
    #             if ( $sibling->{ cluster_id } == $cluster_id) { # find the sibling nodes
    #                 my $target_int_weight = 100 ** $sibling->{ internal_zscore };
    #                 my $int_weight        = $int_sim + $int_zscore + $target_int_weight;
    #                 push(@{ $node->{ links } }, { target_id => $target_id, weight => ($int_weight) } );
    #             }
    #             else {
    #                 my $target_ext_zscore = 2 ** $sibling->{ external_zscore };
    #                 my $target_ext_sim    = 2 ** $node->{ external_similarity };    # store the node's external similarity
    #                 my $target_ext_weight = $target_ext_zscore > 500 ? $target_ext_sim : $target_ext_sim + $target_ext_zscore;
    #                 my $weight = ($ext_weight + $target_ext_weight)/2;
    #                 if ($weight > 1.5 ) { 
    #                     push(@{ $node->{ links } }, { target_id => $target_id, weight => $weight } );
    #                 }     
    #             }
    #         }
    #     }
    # }
    
    ################################ NEW WAY: Links based on SIMAT scores ##############################
    
    
    print STDERR "\@nodes: " . Dumper(@nodes);
    
    # prep data string
    my $data = "{ nodes:[";
    
    my $node_id_count = 0;   # intialize count of node_ids
    
    # print nodes:
    for my $node (@nodes) {
        my $node_name      = $node->{ name } or next;
        my $group          = $node->{ cluster_id };   
        $node->{ node_id } = $node_id_count++;
        $data .= "{ nodeName:'$node_name', group:$group },\n";
    }
    
    # close nodes section, start data
    $data .= ' ], links:[';
    
    # add links to data string
    for my $node (@nodes) {
        my $source_id = $node->{ node_id };
        for my $link (@{ $node->{ links } }) {
            my $target = $nodes[ $link->{ target_id } ]->{ node_id };
            my $value = ($link->{ weight }) * 10 or next;
            $data .= "{ source:$source_id, target:$target, value:$value },\n";
        }
    }
    
    # write end of data string
    $data .= '] }';
    
    print STDERR "\$data: $data\n\n";
    

    $c->stash->{ media_clusters } = $media_clusters;
    $c->stash->{ run }            = $run;
    $c->stash->{ template }       = 'clusters/view.tt2';
    $c->stash->{ data }           = $data;
}

1;
