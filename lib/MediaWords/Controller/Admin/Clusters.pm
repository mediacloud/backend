package MediaWords::Controller::Admin::Clusters;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# set of screens for listing, creating, and viewing the results of clustering runs

use strict;
use warnings;
use parent 'Catalyst::Controller';

use MediaWords::Cluster;
use MediaWords::Cluster::Map;
use MediaWords::DBI::Queries;
use MediaWords::Util::Tags;
use MediaWords::Util::Timing qw( start_time stop_time );

use Data::Dumper;

use POSIX;

# Set a threshold for link weight--links won't be displayed if they're less than this
# This reduces the number of links substantially, making it easier for the client to render
# It also improves the visualization by reducing a lot of noise

sub index : Path : Args(0)
{
    return list( @_ );
}

# create a new cluster run based on the given query, including both creating the media_cluster_runs entry and doing the cluster run
sub create : Local
{
    my ( $self, $c, $queries_id ) = @_;

    my $query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $queries_id );

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/cluster.yml',
            method           => 'post',
            action           => $c->uri_for( "/admin/clusters/create/$queries_id" ),
        }
    );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {

        # gross rule of thumb for optimal number of clusters in kmeans
        my $num_media = MediaWords::DBI::Queries::get_number_of_media_sources( $c->dbis, $query );
        $form->get_field( { name => 'num_clusters' } )->default( POSIX::ceil( sqrt( $num_media / 2 ) ) );

        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'clusters/create.tt2';
        return;
    }

    my $cluster_run = $c->dbis->create(
        'media_cluster_runs',
        {
            clustering_engine => $c->req->param( 'clustering_engine' ),
            queries_id        => $query->{ queries_id },
            num_clusters      => $c->req->param( 'num_clusters' )
        }
    );

    my $clustering_engine = MediaWords::Cluster->new( $c->dbis, $cluster_run );

    $clustering_engine->execute_and_store_media_cluster_run();

    $c->response->redirect( $c->uri_for( '/admin/clusters/view/' . $cluster_run->{ media_cluster_runs_id } ) );
}

sub _get_media_query
{
    my ( $db, $query, $media ) = @_;

    return MediaWords::DBI::Queries::find_or_create_media_sub_query( $db, $query, [ map { $_->{ media_id } } @{ $media } ] );
}

# get the media clusters associated with the media cluster run, including
# fillingin the media and words
sub get_cluster_run_clusters
{
    my ( $self, $c, $cluster_run, $cluster_run_query, $stand_alone ) = @_;

    my $media_clusters = $c->dbis->query(
        "select * from media_clusters where media_cluster_runs_id = $cluster_run->{ media_cluster_runs_id } " .
          "  order by media_clusters_id" )->hashes;

    for my $mc ( @{ $media_clusters } )
    {
        $mc->{ media } = $c->dbis->query( "select distinct m.* from media m, media_clusters_media_map mcmm " .
              "  where m.media_id = mcmm.media_id and mcmm.media_clusters_id = $mc->{ media_clusters_id }" )->hashes;

        my $cluster_words =
          $c->dbis->query( "select *, weight as stem_count from media_cluster_words " .
              "  where media_clusters_id = $mc->{ media_clusters_id } and internal = 't' " .
              "  order by weight desc" )->hashes;

        # $mc->{ query } = _get_media_query( $c->dbis, $cluster_run_query, $mc->{ media } );
        # map { $_->{ query } = _get_media_query( $c->dbis, $cluster_run_query, [ $_ ] ) }@{ $mc->{ media } };
        #
        # my $base_url ="/queries/sentences/$mc->{ query }->{ queries_id }";
        #$mc->{ word_cloud } = MediaWords::Util::WordCloud_Legacy::get_word_cloud( $c, '/', $cluster_words, undef, 1 );
    }

    return $media_clusters;
}

# view the results of a cluster run
sub view : Local
{
    my ( $self, $c, $cluster_runs_id ) = @_;

    my $cluster_run = $c->dbis->find_by_id( 'media_cluster_runs', $cluster_runs_id )
      || die( "Unable to find run $cluster_runs_id" );

    my $stand_alone = $c->req->param( 'stand_alone' );

    my $cluster_run_query = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $cluster_run->{ queries_id } );

    my $media_clusters = $self->get_cluster_run_clusters( $c, $cluster_run, $cluster_run_query, $stand_alone );

    $cluster_run->{ tag_name } = MediaWords::Util::Tags::lookup_tag_name( $c->dbis, $cluster_run->{ tags_id } );

    my $cluster_map;
    if ( my $cluster_maps_id = $c->req->param( 'media_cluster_maps_id' ) )
    {
        $cluster_map = $c->dbis->find_by_id( 'media_cluster_maps', $cluster_maps_id );
    }

    my $cluster_maps = $c->dbis->query(
        "select * from media_cluster_maps where media_cluster_runs_id = $cluster_run->{ media_cluster_runs_id } " .
          "  order by media_cluster_maps_id" )->hashes;

    $c->stash->{ clusters }     = $media_clusters;
    $c->stash->{ cluster_run }  = $cluster_run;
    $c->stash->{ query }        = $cluster_run_query;
    $c->stash->{ cluster_maps } = $cluster_maps;
    $c->stash->{ cluster_map }  = $cluster_map;

    if ( $stand_alone )
    {
        $c->stash->{ template } = 'clusters/view_standalone.tt2';
    }
    else
    {
        $c->stash->{ template } = 'clusters/view.tt2';
    }
}

# view time slices of the given cluster map for every four weeks
sub view_time_slice_map : Local
{
    my ( $self, $c, $cluster_runs_id ) = @_;

    my $cluster_run = $c->dbis->find_by_id( 'media_cluster_runs', $cluster_runs_id )
      || die( "Unable to find cluster run '$cluster_runs_id'" );

    $cluster_run->{ query } = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $cluster_run->{ queries_id } );

    my $cluster_maps_id = $c->req->param( 'media_cluster_maps_id' ) || die( "no cluster maps id" );
    my $cluster_map = $c->dbis->find_by_id( 'media_cluster_maps', $cluster_maps_id )
      || die( "Unable to find cluster map '$cluster_maps_id'" );
    $cluster_map->{ query } = $cluster_run->{ query };

    my $time_slice_maps = MediaWords::Cluster::Map::get_time_slice_maps( $c->dbis, $cluster_run, $cluster_map );

    # my $media_clusters = $self->get_cluster_run_clusters( $c, $cluster_run, $cluster_run->{ query }, 1 );

    #$c->stash->{ clusters }         = $media_clusters;
    $c->stash->{ cluster_run }  = $cluster_run;
    $c->stash->{ query }        = $cluster_run->{ query };
    $c->stash->{ cluster_maps } = [ $cluster_map, @{ $time_slice_maps } ];

    $c->stash->{ template } = 'clusters/view_time_slice_maps.tt2';
}

# create the form for processing a unipolar cluster map
sub create_polar_map : Local
{
    my ( $self, $c, $cluster_runs_id ) = @_;

    my $cluster_run = $c->dbis->find_by_id( 'media_cluster_runs', $cluster_runs_id )
      || die( "Unable to find cluster run '$cluster_runs_id'" );

    $cluster_run->{ query } = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $cluster_run->{ queries_id } );

    my $bipolar = $c->req->param( 'bipolar' );

    my $form_config = $bipolar ? 'cluster_bipolar_map.yml' : 'cluster_unipolar_map.yml';

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/' . $form_config,
            method           => 'post',
            action           => $c->uri_for( "/admin/clusters/create_polar_map/$cluster_runs_id" ),
        }
    );

    my $media_set_options       = MediaWords::DBI::Queries::get_media_set_options( $c->dbis );
    my $dashboard_topic_options = MediaWords::DBI::Queries::get_dashboard_topic_options( $c->dbis );

    $form->get_fields( { name => 'media_sets_ids_1' } )->[ 0 ]->options( $media_set_options );
    $form->get_fields( { name => 'dashboard_topics_ids_1' } )->[ 0 ]->options( $dashboard_topic_options );

    if ( $bipolar )
    {
        $form->get_fields( { name => 'media_sets_ids_2' } )->[ 0 ]->options( $media_set_options );
        $form->get_fields( { name => 'dashboard_topics_ids_2' } )->[ 0 ]->options( $dashboard_topic_options );
    }

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ cluster_run } = $cluster_run;
        $c->stash->{ form }        = $form;
        $c->stash->{ bipolar }     = $bipolar;
        $c->stash->{ template }    = 'clusters/create_polar_map.tt2';
        return;
    }

    my $queries = [ MediaWords::DBI::Queries::find_or_create_query_by_request( $c->dbis, $c->req, '_1' ) ];
    if ( $c->req->param( 'start_date_2' ) )
    {
        push( @{ $queries }, MediaWords::DBI::Queries::find_or_create_query_by_request( $c->dbis, $c->req, '_2' ) );
    }

    my $cluster_map =
      MediaWords::Cluster::Map::generate_cluster_map( $c->dbis, $cluster_run, 'polar', $queries, 0, 'graphviz-neato' );

    $c->response->redirect(
        $c->uri_for(
            '/admin/clusters/view/' . $cluster_run->{ media_cluster_runs_id },
            { media_cluster_maps_id => $cluster_map->{ media_cluster_maps_id } }
        )
    );

}

# create a new cluster map for the given cluster run
sub create_cluster_map : Local
{
    my ( $self, $c, $cluster_runs_id ) = @_;

    my $cluster_run = $c->dbis->find_by_id( 'media_cluster_runs', $cluster_runs_id )
      || die( "Unable to find cluster run '$cluster_runs_id'" );

    my $form = $c->create_form( { load_config_file => $c->path_to . '/root/forms/cluster_map.yml' } );
    $form->process( $c->request );
    if ( !$form->submitted_and_valid )
    {
        $cluster_run->{ query } = MediaWords::DBI::Queries::find_query_by_id( $c->dbis, $cluster_run->{ queries_id } );
        my $num_media = MediaWords::DBI::Queries::get_number_of_media_sources( $c->dbis, $cluster_run->{ query } );
        my $max_links = int( $num_media * log( $num_media ) );

        $form->get_fields( { name => 'max_links' } )->[ 0 ]->value( $max_links );

        $c->stash->{ cluster_run } = $cluster_run;
        $c->stash->{ max_links }   = $max_links;
        $c->stash->{ form }        = $form;
        $c->stash->{ template }    = 'clusters/create_cluster_map.tt2';
        return;
    }

    my $max_links = $c->req->param( 'max_links' );
    my $method    = $c->req->param( 'method' );

    my $cluster_map =
      MediaWords::Cluster::Map::generate_cluster_map( $c->dbis, $cluster_run, 'cluster', undef, $max_links, $method );

    $c->response->redirect(
        $c->uri_for(
            '/admin/clusters/view/' . $cluster_run->{ media_cluster_runs_id },
            { media_cluster_maps_id => $cluster_map->{ media_cluster_maps_id } }
        )
    );
}

1;
