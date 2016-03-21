package MediaWords::Controller::Api::V2::Tags;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

use MediaWords::Controller::Api::V2::MC_REST_SimpleObject;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config(
    action => {
        single_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list_GET   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        update_PUT => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub get_name_search_clause
{
    my ( $self, $c ) = @_;

    my $v = $c->req->params->{ search };

    return '' unless ( $v );

    return 'and false' unless ( length( $v ) > 2 );

    my $qv = $c->dbis->dbh->quote( $v );

    return <<END;
and tags_id in (
    select t.tags_id
        from tags t
            join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
        where
            t.tag ilike '%' || $qv || '%' or
            t.label ilike '%' || $qv || '%' or
            ts.name ilike '%' || $qv || '%' or
            ts.label ilike '%' || $qv || '%'
)
END
}

sub get_table_name
{
    return "tags";
}

sub list_optional_query_filter_field
{
    return 'tag_sets_id';
}

sub single_GET : Local
{
    my ( $self, $c, $id ) = @_;

    my $items = $c->dbis->query( <<END, $id )->hashes();
select t.tags_id, t.tag_sets_id, t.label, t.description, t.tag,
        ts.name tag_set_name, ts.label tag_set_label, ts.description tag_set_description,
        t.show_on_media OR ts.show_on_media show_on_media,
        t.show_on_stories OR ts.show_on_stories show_on_stories
    from tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        t.tags_id = ?
END

    $self->status_ok( $c, entity => $items );
}

sub _fetch_list($$$$$$)
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    my $public = $c->req->params->{ public } || '';

    my $public_clause =
      $public eq '1' ? 't.show_on_media or ts.show_on_media or t.show_on_stories or ts.show_on_stories' : '1=1';

    $c->dbis->query( <<END );
create temporary view tags as
    select t.tags_id, t.tag_sets_id, t.label, t.description, t.tag,
        ts.name tag_set_name, ts.label tag_set_label, ts.description tag_set_description,
        t.show_on_media OR ts.show_on_media show_on_media,
        t.show_on_stories OR ts.show_on_stories show_on_stories
    from tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where $public_clause
END

    return $self->SUPER::_fetch_list( $c, $last_id, $table_name, $id_field, $rows );
}

sub update : Local : ActionClass('REST')
{
}

sub update_PUT : Local
{
    my ( $self, $c, $id ) = @_;

    my $tag_name    = $c->req->params->{ 'tag' };
    my $label       = $c->req->params->{ 'label' };
    my $description = $c->req->params->{ 'description' };

    my $tag = $c->dbis->find_by_id( 'tags', $id );

    die 'tag not found ' unless defined( $tag );

    my $tag_set = $c->dbis->find_by_id( 'tag_sets', $tag->{ tag_sets_id } );

    die 'tag set not found ' unless defined( $tag_set );

    $self->die_unless_user_can_edit_tag_set_tag_descriptors( $c, $tag_set );

    if ( defined( $tag_name ) )
    {
        say STDERR "updating tag name to '$tag_name'";
        $c->dbis->query( "UPDATE tags set tag = ? where tags_id = ? ", $tag_name, $id );
    }

    if ( defined( $label ) )
    {
        say STDERR "updating label to '$label'";
        $c->dbis->query( "UPDATE tags set label = ? where tags_id = ? ", $label, $id );
    }

    if ( defined( $description ) )
    {
        say STDERR "updating description to '$description'";
        $c->dbis->query( "UPDATE tags set description = ? where tags_id = ? ", $description, $id );
    }

    die unless defined( $tag_name ) || defined( $label ) || defined( $description );

    $tag_set = $c->dbis->find_by_id( 'tags', $id );

    $self->status_ok( $c, entity => $tag_set );

    return;
}

1;
