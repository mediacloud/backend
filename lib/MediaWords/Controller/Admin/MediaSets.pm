package MediaWords::Controller::Admin::MediaSets;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use MediaWords::DBI::MediaSets;
use parent 'Catalyst::Controller';

# list all media_sets with a set_type of collection
#
# we just the collection type b/c the medium type type sets are created
# automagically from the collection type
sub list : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    $dashboards_id || die( "no dashboards_id in path" );

    my $media_sets = $c->dbis->query(
        "select ms.*, dms.dashboard_media_sets_id " .
          "  from media_sets ms left join dashboard_media_sets dms on ( ms.media_sets_id = dms.media_sets_id ) " .
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

# create a collection media_set with attendant medium media_sets as well as the
# media_set_media_map entries for the media_sets and for its medium media set children
sub create_collection_media_set
{
    my ( $self, $c, $name, $tags_id, $description ) = @_;

    my $media_set =
      $c->dbis->create( 'media_sets',
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
            action           => $c->uri_for( "/admin/mediasets/create/$dashboards_id" ),
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

    my $name        = $c->req->param( 'name' );
    my $description = $c->req->param( 'description' );

    $c->dbis->begin_work;

    my $media_set = $self->create_collection_media_set( $c, $name, $tag->{ tags_id }, $description );
    $c->dbis->create( 'dashboard_media_sets',
        { dashboards_id => $dashboards_id, media_sets_id => $media_set->{ media_sets_id } } );

    $c->dbis->commit;

    $c->response->redirect( $c->uri_for( "/admin/mediasets/list/$dashboards_id", { status_msg => 'media set created.' } ) );
}

1;
