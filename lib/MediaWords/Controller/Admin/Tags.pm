package MediaWords::Controller::Admin::Tags;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

use parent 'Catalyst::Controller';

# create a new media_set of set_type collection
sub edit : Local
{
    my ( $self, $c, $tags_id ) = @_;

    die( "no dashboards_id in path" ) unless ( $tags_id );

    my $db = $c->dbis;

    my $tag = $db->find_by_id( 'tags', $tags_id ) || die( "unable to find tag '$tags_id'" );

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/tag.yml',
            method           => 'post',
            action           => $c->uri_for( "/admin/tags/edit/$tags_id" ),
        }
    );

    $form->default_values( $tag );
    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'tags/edit.tt2';
        return;
    }

    map { $tag->{ $_ } = $c->req->params->{ $_ } } qw(tag label description show_on_media show_on_stories);

    $db->update_by_id( 'tags', $tags_id, $tag );

    $c->response->redirect( $c->uri_for( "/admin/tags/edit/$tags_id", { status_msg => 'tag saved.' } ) );
}

1;
