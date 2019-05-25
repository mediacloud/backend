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
        single => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        update => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
        create => { Does => [ qw( ~MediaEditAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub get_name_search_clause
{
    my ( $self, $c ) = @_;

    my $tag_search = $c->req->params->{ search };

    unless ( $tag_search )
    {
        return '';
    }

    unless ( length( $tag_search ) > 2 )
    {
        return 'AND false';
    }

    my $db                 = $c->dbis;
    my $escaped_tag_search = $db->quote( $tag_search );

    # Return the FTS condition back to _fetch_list() instead of creating
    # temporary tables with *all* found tags as then the executor can run more
    # effective plans thanks to "tags_id" offset and LIMIT
    return <<"SQL";
        AND to_tsvector('english', tag || ' ' || label)
            @@ plainto_tsquery('english', $escaped_tag_search)
SQL
}

sub get_table_name
{
    return "tags";
}

sub get_extra_where_clause
{
    my ( $self, $c ) = @_;

    my $clauses = [];

    if ( my $tag_sets_ids = $c->req->params->{ tag_sets_id } )
    {
        $tag_sets_ids = ref( $tag_sets_ids ) ? $tag_sets_ids : [ $tag_sets_ids ];
        my $tag_sets_ids_list = join( ',', map { int( $_ ) } @{ $tag_sets_ids } );
        push( @{ $clauses }, "and tag_sets_id in ( $tag_sets_ids_list )" );
    }

    if ( my $similar_tags_id = int( $c->req->params->{ similar_tags_id } // 0 ) )
    {
        push( @{ $clauses }, <<SQL );
and tags_id in (
    select b.tags_id
        from media_tags_map a
            join media_tags_map b using ( media_id )
        where
            a.tags_id = $similar_tags_id and
            a.tags_id <> b.tags_id
        group by b.tags_id
        order by count(*) desc
        limit 100
)
SQL
    }

    if ( @{ $clauses } )
    {
        return join( ' ', @{ $clauses } );
    }

    return '';
}

sub single_GET
{
    my ( $self, $c, $id ) = @_;

    my $items = $c->dbis->query( <<END, $id )->hashes();
select t.tags_id, t.tag_sets_id, t.label, t.description, t.tag,
        ts.name tag_set_name, ts.label tag_set_label, ts.description tag_set_description,
        COALESCE(t.show_on_media, 'f') OR COALESCE(ts.show_on_media, 'f') AS show_on_media,
        COALESCE(t.show_on_stories, 'f') OR COALESCE(ts.show_on_stories, 'f') AS show_on_stories,
        t.is_static
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

    my $public = int( $c->req->params->{ public } // 0 );

    my $public_clause = $public ? 't.show_on_media or ts.show_on_media or t.show_on_stories or ts.show_on_stories' : '1=1';

    $c->dbis->query( <<END );
create temporary view tags as
    select t.tags_id, t.tag_sets_id, t.label, t.description, t.tag,
        ts.name tag_set_name, ts.label tag_set_label, ts.description tag_set_description,
        t.show_on_media OR ts.show_on_media show_on_media,
        t.show_on_stories OR ts.show_on_stories show_on_stories,
        t.is_static
    from tags t
        join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where $public_clause
END

    return $self->SUPER::_fetch_list( $c, $last_id, $table_name, $id_field, $rows );
}

sub get_update_fields($)
{
    return [ qw/tag label description show_on_media show_on_stories is_static tag_sets_id/ ];
}

sub update : Local : ActionClass('MC_REST')
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/tags_id/ ] );

    my $tag = $c->dbis->require_by_id( 'tags', $data->{ tags_id } );
    my $tag_set = $c->dbis->require_by_id( 'tag_sets', $data->{ tag_sets_id } ) if ( $data->{ tag_sets_id } );

    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $self->get_update_fields } };

    my $allow_null = 1;
    $input->{ show_on_media }   = normalize_boolean_for_db( $input->{ show_on_media },   $allow_null );
    $input->{ show_on_stories } = normalize_boolean_for_db( $input->{ show_on_stories }, $allow_null );
    $input->{ is_static }       = normalize_boolean_for_db( $input->{ is_static } );

    my $updated_tag = $c->dbis->update_by_id( 'tags', $data->{ tags_id }, $input );

    return $self->status_ok( $c, entity => { tag => $updated_tag } );
}

sub create : Local : ActionClass( 'MC_REST' )
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    $self->require_fields( $c, [ qw/tag_sets_id tag label/ ] );

    my $fields = [ 'tag_sets_id', @{ $self->get_update_fields } ];
    my $input = { map { $_ => $data->{ $_ } } grep { exists( $data->{ $_ } ) } @{ $fields } };

    my $allow_null = 1;
    $input->{ show_on_media }   = normalize_boolean_for_db( $input->{ show_on_media },   $allow_null );
    $input->{ show_on_stories } = normalize_boolean_for_db( $input->{ show_on_stories }, $allow_null );
    $input->{ is_static }       = normalize_boolean_for_db( $input->{ is_static } );

    my $created_tag = $c->dbis->create( 'tags', $input );

    return $self->status_ok( $c, entity => { tag => $created_tag } );
}

1;
