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
        my $media = $db->query( <<END, $tag->{ tags_id } )->hashes;
select m.* 
    from media m
        join media_tags_map mtm on ( m.media_id = mtm.media_id )
    where mtm.tags_id = ?
END

        my $stories = $db->query( <<END, $tag->{ tags_id } )->hashes;
select s.*
    from stories s
        join stories_tags_map stm on ( s.stories_id = stm.stories_id )
    where stm.tags_id = ?
    limit 100
END

        $c->stash->{ tag }      = $tag;
        $c->stash->{ media }    = $media;
        $c->stash->{ stories }  = $stories;
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'tags/edit.tt2';
        return;
    }

    map { $tag->{ $_ } = $c->req->params->{ $_ } } qw(tag label description show_on_media show_on_stories);

    $db->update_by_id( 'tags', $tags_id, $tag );

    my $next_tag = $db->query( <<END, $tag->{ tags_id }, $tag->{ tag_sets_id } )->hash;
select * from tags
    where
        ( label is null or description is null ) and
        tag_sets_id = \$2
    order by ( tags_id > \$1 ) desc, tags_id asc
END

    my $url = $next_tag ? "/admin/tags/edit/$next_tag->{ tags_id }" : "/search/tags/$tag->{ tag_sets_id }";

    $c->response->redirect( $c->uri_for( $url, { status_msg => 'Tag saved.' } ) );
}

1;
