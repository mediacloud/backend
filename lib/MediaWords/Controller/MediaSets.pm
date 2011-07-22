package MediaWords::Controller::MediaSets;

use strict;
use warnings;
use MediaWords::DBI::MediaSets;
use parent 'Catalyst::Controller';

# list all media_sets with a set_type of collection
#
# we just the collection type b/c the medium type and cluster type sets are created
# automagically from the collection type
sub list : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    $dashboards_id || die( "no dashboards_id in path" );

    my $media_sets = $c->dbis->query(
        "select ms.*, mcr.media_cluster_runs_id, mcr.queries_id as cluster_run_name, dms.dashboard_media_sets_id " .
          "  from media_sets ms left join dashboard_media_sets dms on ( ms.media_sets_id = dms.media_sets_id ) " .
          "    left join media_cluster_runs mcr on ( dms.media_cluster_runs_id = mcr.media_cluster_runs_id ) " .
          "  where ms.set_type = 'collection' and dms.dashboards_id = ? " . "  order by media_sets_id",
        $dashboards_id
    )->hashes;

    map { $_->{ tag_name } = MediaWords::Util::Tags::lookup_tag_name( $c->dbis, $_->{ tags_id } ) } @{ $media_sets };

    $c->stash->{ dashboards_id } = $dashboards_id;
    $c->stash->{ media_sets }    = $media_sets;

    $c->stash->{ template } = 'mediasets/list.tt2';
}

# create a medium media_set for the given medium if it does not already exist
sub create_medium_media_set
{
    my ( $self, $c, $medium ) = @_;

    my $media_set =
      $c->dbis->query( "select * from media_sets where set_type = 'medium' and media_id = ?", $medium->{ media_id } )->hash;
    if ( $media_set )
    {
        return;
    }

    MediaWords::DBI::MediaSets::create_for_medium( $c->dbis, $medium );
}

# create a cluster media_set for the given cluster.
#
# create a media_set for every medium contained within the cluser.
#
# die if the cluster already has a media_set associated with it so that the name (which should
# include the name of the parent collection_media_set) does not get mismatched
sub create_cluster_media_set
{
    my ( $self, $c, $media_cluster, $collection_media_set ) = @_;

    my $media_set = $c->dbis->query( "select * from media_sets where set_type = 'cluster' and media_clusters_id = ?",
        $media_cluster->{ media_clusters_id } )->hash;
    if ( $media_set )
    {
        die( "media_set already exists for cluster '$media_cluster->{ media_clusters_id }'" );
    }

    my $name = "$collection_media_set->{ name } / $media_cluster->{ description }";
    $media_set = $c->dbis->create(
        'media_sets',
        {
            set_type          => 'cluster',
            name              => $name,
            media_clusters_id => $media_cluster->{ media_clusters_id }
        }
    );

    my $media = $c->dbis->query(
        "select m.* from media m, media_clusters_media_map mcmm " .
          "  where m.media_id = mcmm.media_id and mcmm.media_clusters_id = ?",
        $media_cluster->{ media_clusters_id }
    )->hashes;
    for my $medium ( @{ $media } )
    {
        $self->create_medium_media_set( $c, $medium );

        $c->dbis->create(
            'media_sets_media_map',
            {
                media_sets_id => $media_set->{ media_sets_id },
                media_id      => $medium->{ media_id }
            }
        );
    }
}

# create a collection media_set with attendant medium media_sets and cluster media sets as well as the
# media_set_media_map entries for the media_sets and for its medium and cluster media set children
sub create_collection_media_set
{
    my ( $self, $c, $name, $tags_id, $description ) = @_;

    my $media_set = $c->dbis->create( 'media_sets', 
        { name => $name, description => $description, set_type => 'collection', tags_id => $tags_id } );
    my $media = $c->dbis->query(
        "select m.* from media m, media_tags_map mtm " . "  where m.media_id = mtm.media_id and mtm.tags_id = ?", $tags_id )
      ->hashes;
    for my $medium ( @{ $media } )
    {
        $self->create_medium_media_set( $c, $medium );

        $c->dbis->create(
            'media_sets_media_map',
            {
                media_id      => $medium->{ media_id },
                media_sets_id => $media_set->{ media_sets_id }
            }
        );
    }

    # my $media_clusters = $c->dbis->query( "select * from media_clusters " .
    #                                       "  where media_cluster_runs_id = ?", $media_cluster_runs_id )->hashes;
    # for my $cluster ( @{ $media_clusters } )
    # {
    #     $self->create_cluster_media_set( $c, $cluster, $media_set );
    # }

    return $media_set;
}

# create a new media_set of set_type collection
sub create : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    $dashboards_id || die( "no dashboards_id in path" );

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/mediaset.yml',
            method           => 'post',
            action           => $c->uri_for( "/mediasets/create/$dashboards_id" ),
        }
    );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'mediasets/create.tt2';
        return;
    }

    my $tag = MediaWords::Util::Tags::lookup_tag( $c->dbis, $c->request->param( 'tag_name' ) );
    if ( !$tag )
    {
        $c->stash->{ form }      = $form;
        $c->stash->{ error_msg } = "Unable to find tag '" . $c->request->param( 'tag_name' ) . "'";
        $c->stash->{ template }  = 'mediasets/create.tt2';
        return;
    }

    my $name                  = $c->req->param( 'name' );
    my $description           = $c->req->param( 'description' );
    my $media_cluster_runs_id = $c->req->param( 'media_cluster_runs_id' );

    $c->dbis->begin_work;

    my $media_set = $self->create_collection_media_set( $c, $name, $tag->{ tags_id }, $description );
    $c->dbis->create( 'dashboard_media_sets',
        { dashboards_id => $dashboards_id, media_sets_id => $media_set->{ media_sets_id } } );

    $c->dbis->commit;

    $c->response->redirect( $c->uri_for( "/mediasets/list/$dashboards_id", { status_msg => 'media set created.' } ) );
}

# edit the media_cluster_run selection for the dashboad_media_set
sub edit_cluster_run : Local
{
    my ( $self, $c, $dashboard_media_sets_id ) = @_;

    $dashboard_media_sets_id || die( "no dashboard_media_sets_id" );

    my $dashboard_media_set = $c->dbis->find_by_id( 'dashboard_media_sets', $dashboard_media_sets_id );

    my $media_cluster_runs = $c->dbis->query(
        "select mcr.* from media_cluster_runs mcr, dashboard_media_sets dms " .
          "  where mcr.media_cluster_runs_id = dms.media_cluster_runs_id and dms.dashboard_media_sets_id = ? " .
          "  order by mcr.media_cluster_runs_id ",
        $dashboard_media_sets_id
    )->hashes;

    $c->stash->{ dashboard_media_set } = $dashboard_media_set;
    $c->stash->{ media_cluster_runs }  = $media_cluster_runs;
    $c->stash->{ template }            = 'mediasets/edit_cluster_run.tt2';
}

sub edit_cluster_run_do : Local
{
    my ( $self, $c, $dashboard_media_sets_id ) = @_;

    $dashboard_media_sets_id || die( "no dashboard_media_sets_id" );

    my $dashboard_media_set = $c->dbis->find_by_id( 'dashboard_media_sets', $dashboard_media_sets_id );
    my $media_set           = $c->dbis->find_by_id( 'media_sets',           $dashboard_media_set->{ media_sets_id } );

    my $media_cluster_runs_id = $c->req->param( 'media_cluster_runs_id' ) || die( "no media_cluster_runs_id" );

    $c->dbis->query( "update dashboard_media_sets set media_cluster_runs_id = ? " . "  where dashboard_media_sets_id = ?",
        $media_cluster_runs_id, $dashboard_media_sets_id );

    my $media_clusters =
      $c->dbis->query( "select * from media_clusters " . "  where media_cluster_runs_id = ?", $media_cluster_runs_id )
      ->hashes;
    for my $cluster ( @{ $media_clusters } )
    {
        $self->create_cluster_media_set( $c, $cluster, $media_set );
    }

    $c->response->redirect(
        $c->uri_for(
            "/mediasets/list/$dashboard_media_set->{ dashboards_id }",
            { status_msg => 'Media Set Cluster Run added.' }
        )
    );
}

1;
