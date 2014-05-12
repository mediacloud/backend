package MediaWords::Controller::Admin::TagSets;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

use parent 'Catalyst::Controller';

# create a new tag_set
sub edit : Local
{
    my ( $self, $c, $tag_sets_id ) = @_;

    die( "no tag_sets_id in path" ) unless ( $tag_sets_id );

    my $db = $c->dbis;

    my $tag_set = $db->find_by_id( 'tag_sets', $tag_sets_id ) || die( "unable to find tag_set '$tag_sets_id'" );

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/tag_set.yml',
            method           => 'post',
            action           => $c->uri_for( "/admin/tagsets/edit/$tag_sets_id" ),
        }
    );

    $form->default_values( $tag_set );
    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'tag_sets/edit.tt2';
        return;
    }

    map { $tag_set->{ $_ } = $c->req->params->{ $_ } } qw(name label description show_on_media show_on_stories);

    $db->update_by_id( 'tag_sets', $tag_sets_id, $tag_set );

    $c->response->redirect( $c->uri_for( "/search/tag_sets", { status_msg => 'tag set saved.' } ) );
}

1;
