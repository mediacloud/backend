package MediaWords::Controller::Api::V2::MC_REST_SimpleObject;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;
use strict;
use warnings;
use base 'Catalyst::Controller::REST';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;

=head1 NAME

MediaWords::Controller::Media - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

# Default authentication action roles
__PACKAGE__->config(    #
    action => {         #
        single_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
        list_GET   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
      }    #
);         #

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub _purge_extra_fields
{
    my ( $self, $obj ) = @_;

    my $new_obj = {};

    foreach my $default_output_field ( @{ $self->default_output_fields() } )
    {
        $new_obj->{ $default_output_field } = $obj->{ $default_output_field };
    }

    return $new_obj;
}

sub _purge_extra_fields_obj_list
{
    my ( $self, $list ) = @_;

    return [ map { $self->_purge_extra_fields( $_ ) } @{ $list } ];
}

sub _purge_non_permissible_fields
{
    my ( $self, $obj ) = @_;

    my $object_fields = keys %{ $obj };

    my $permissible_output_fields = $self->permissible_output_fields();

    my $new_obj = { map { $_ => $obj->{ $_ } } @$permissible_output_fields };

    return $new_obj;
}

sub _purge_non_permissible_fields_obj_list
{
    my ( $self, $list ) = @_;

    return [ map { $self->_purge_non_permissible_fields( $_ ) } @{ $list } ];
}

sub default_output_fields
{
    return;
}

sub permissible_output_fields
{
    return;
}

sub has_nested_data
{
    return;
}

sub get_table_name
{
    die "Method not implemented";
}

sub has_extra_data
{
    return;
}

sub add_extra_data
{
    return;
}

sub _process_result_list
{
    my ( $self, $c, $items, $all_fields ) = @_;

    if ( $self->default_output_fields() && !$all_fields )
    {
        $items = $self->_purge_extra_fields_obj_list( $items );
    }

    if ( $self->has_extra_data() )
    {
        $items = $self->add_extra_data( $c, $items );
    }

    if ( $self->has_nested_data() )
    {

        my $nested_data = $c->req->param( 'nested_data' );
        $nested_data //= 1;

        if ( $nested_data )
        {
            $self->_add_nested_data( $c->dbis, $items );
        }
    }

    if ( $self->permissible_output_fields() )
    {
        $items = $self->_purge_non_permissible_fields_obj_list( $items );
    }

    return $items;
}

sub single : Local : ActionClass('REST')    # action roles are to be set for each derivative sub-actions
{
}

sub single_GET : Local
{
    my ( $self, $c, $id ) = @_;

    my $table_name = $self->get_table_name();

    my $id_field = $table_name . "_id";

    my $query = "select * from $table_name where $id_field = ? ";

    my $all_fields = $c->req->param( 'all_fields' );
    $all_fields //= 0;

    my $items = $c->dbis->query( $query, $id )->hashes();

    $items = $self->_process_result_list( $c, $items, $all_fields );

    $self->status_ok( $c, entity => $items );
}

sub list_query_filter_field
{
    return;
}

sub list_api_requires_filter_field
{
    my ( $self ) = @_;

    return defined( $self->list_query_filter_field() ) && $self->list_query_filter_field();
}

sub list_optional_query_filter_field
{
    return;
}

sub list_name_search_field
{
    return;
}

sub get_name_search_clause
{
    my ( $self, $c ) = @_;

    my $name_clause = '';

    my $name_field = $self->list_name_search_field;

    return '' unless ( $name_field );

    my $name_val = $c->req->params->{ $name_field };

    return '' unless ( $name_val );

    return 'and false' unless ( length( $name_val ) > 2 );

    my $q_name_val = $c->dbis->dbh->quote( $name_val );

    return "and $name_field ilike '%' || $q_name_val || '%'";
}

# list_query_filter_field or list_optional_query_field, add relevant clauses
# for any specified fields that have values specified in the requests params
sub _get_filter_field_clause
{
    my ( $self, $c ) = @_;

    my $clauses = [];
    my $required_field_names = $self->list_query_filter_field || [];
    $required_field_names = ref( $required_field_names ) ? $required_field_names : [ $required_field_names ];
    for my $required_field_name ( @{ $required_field_names } )
    {
        my $val = $c->req->params->{ $required_field_name };
        die( "Missing required param $required_field_name" ) unless ( defined( $val ) );

        push( @{ $clauses }, "$required_field_name = " . $c->dbis->dbh->quote( $val ) );
    }

    my $field_names = $self->list_optional_query_filter_field || [];
    $field_names = ref( $field_names ) ? $field_names : [ $field_names ];
    for my $field_name ( @{ $field_names } )
    {
        my $val = $c->req->params->{ $field_name };

        if ( $val )
        {
            push( @{ $clauses }, "$field_name = " . $c->dbis->dbh->quote( $val ) );
        }
    }

    return '' if ( !@{ $clauses } );

    return ' and ( ' . join( ' and ', @{ $clauses } ) . ' ) ';
}

sub order_by_clause
{
    my ( $self ) = @_;

    return;
}

sub get_extra_where_clause
{
    return '';
}

sub _fetch_list
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    my $list;

    my $name_clause         = $self->get_name_search_clause( $c );
    my $filter_field_clause = $self->_get_filter_field_clause( $c );
    my $extra_where_clause  = $self->get_extra_where_clause( $c );
    my $order_by_clause     = $self->order_by_clause || "$id_field asc";

    my $query = <<END;
select * 
    from $table_name 
    where 
        $id_field > ? $name_clause 
        $extra_where_clause 
        $filter_field_clause 
    order by $order_by_clause limit ?
END

    $list = $c->dbis->query( $query, $last_id, $rows )->hashes;

    return $list;
}

sub _get_list_last_id_param_name
{
    my ( $self, $c ) = @_;

    my $table_name = $self->get_table_name();

    my $id_field = $table_name . "_id";

    my $last_id_param_name = 'last_' . $id_field;

    return $last_id_param_name;
}

sub list : Local : ActionClass('REST')    # action roles are to be set for each derivative sub-actions
{
}

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    # say STDERR "starting list_GET";

    my $table_name = $self->get_table_name();

    my $id_field = $table_name . "_id";

    my $last_id_param_name = $self->_get_list_last_id_param_name( $c );

    my $last_id = $c->req->param( $last_id_param_name );
    $last_id //= 0;

    # say STDERR "last_id: $last_id";

    my $all_fields = $c->req->param( 'all_fields' );
    $all_fields //= 0;

    my $rows = $c->req->param( 'rows' );
    $rows //= ROWS_PER_PAGE;

    # say STDERR "rows $rows";

    my $list = $self->_fetch_list( $c, $last_id, $table_name, $id_field, $rows );

    $list = $self->_process_result_list( $c, $list, $all_fields );

    $self->status_ok( $c, entity => $list );
}

sub _die_unless_tag_set_matches_user_email
{
    my ( $self, $c, $tags_id ) = @_;

    Readonly my $query =>
      "SELECT tag_sets.name from tags, tag_sets where tags.tag_sets_id = tag_sets.tag_sets_id AND tags_id = ? limit 1 ";

    my $hashes = $c->dbis->query( $query, $tags_id )->hashes();

    #say STDERR "Hashes:\n" . Dumper( $hashes );

    my $tag_set = $hashes->[ 0 ]->{ name };

    die "Undefined tag_set for tags_id: $tags_id" unless defined( $tag_set );

    die "Illegal tag_set name '$tag_set', tag_set must be user email "
      unless $c->stash->{ api_auth }->{ email } eq $tag_set;
}

#tag_set permissions apply_tags, create_tags, edit_tag_set_descriptors, edit_tag_descriptors

sub _die_unless_user_can_apply_tag_set_tags
{
    my ( $self, $c, $tag_set ) = @_;

    return if $c->stash->{ api_auth }->{ email } eq $tag_set->{ name };

    die;
}

sub _die_unless_user_can_create_tag_set_tags
{
    my ( $self, $c, $tag_set ) = @_;

    return if $c->stash->{ api_auth }->{ email } eq $tag_set->{ name };

    die;
}

sub _die_unless_user_can_edit_tag_set_descriptors
{
    my ( $self, $c, $tag_set ) = @_;

    return if $c->stash->{ api_auth }->{ email } eq $tag_set->{ name };

    die;
}

sub _die_unless_user_can_edit_tag_set_tag_descriptors
{
    my ( $self, $c, $tag_set ) = @_;

    return if $c->stash->{ api_auth }->{ email } eq $tag_set->{ name };

    die;
}

sub _get_tags_id
{
    my ( $self, $c, $tag_string ) = @_;

    if ( $tag_string =~ /^\d+/ )
    {
        # say STDERR "returning int: $tag_string";
        return $tag_string;
    }
    elsif ( $tag_string =~ /^.+:.+$/ )
    {
        # say STDERR "processing tag_sets:tag_name";

        my ( $tag_set_name, $tag_name ) = split ':', $tag_string;

        #say STDERR Dumper( $c->stash );
        my $user_email = $c->stash->{ api_auth }->{ email };

        my $tag_sets = $c->dbis->query( "SELECT * from tag_sets where name = ?", $tag_set_name )->hashes;

        if ( !scalar( @$tag_sets ) > 0 )
        {
            if ( $user_email ne $tag_set_name )
            {
                die "Illegal tag_set name '" . $tag_set_name . "' tag_set must be user email ( '$user_email' ) ";
            }

            $tag_sets = [ $c->dbis->create( 'tag_sets', { 'name' => $tag_set_name } ) ];
        }

        die "invalid tag set " unless scalar( @$tag_sets ) > 0;

        # say STDERR "tag_sets";
        # say STDERR Dumper( $tag_sets );

        my $tag_set     = $tag_sets->[ 0 ];
        my $tag_sets_id = $tag_set->{ tag_sets_id };

        $self->_die_unless_user_can_apply_tag_set_tags( $c, $tag_set );

        my $tags =
          $c->dbis->query( "SELECT * from tags where tag_sets_id = ? and tag = ? ", $tag_sets_id, $tag_name )->hashes;

        # say STDERR Dumper( $tags );

        my $tag;

        if ( !scalar( @$tags ) )
        {
            $self->_die_unless_user_can_create_tag_set_tags( $c, $tag_set );
            $tag = $c->dbis->create( 'tags', { tag => $tag_name, tag_sets_id => $tag_sets_id } );
        }
        else
        {
            $tag = $tags->[ 0 ];
        }

        return $tag->{ tags_id };
    }
    else
    {
        die "invalid tag string '$tag_string'";
    }

    return;
}

# given a hash in the form { $id => [ $tags_id, ... ] }, for each
# distinct tag_set associated with the listed tags for a story/sentence, clear
# all other tags in that tag set from the story/sentence
sub _clear_tags
{
    my ( $self, $c, $tags_map ) = @_;

    my $tags_map_table = $self->get_table_name() . '_tags_map';
    my $table_id_name  = $self->get_table_name() . '_id';

    while ( my ( $id, $tags_ids ) = each( %{ $tags_map } ) )
    {
        my $tags_ids_list = join( ',', @{ $tags_ids } );
        $c->dbis->query( <<END, $id );
delete from $tags_map_table stm
    using tags keep_tags, tags delete_tags
    where
        keep_tags.tags_id in ( $tags_ids_list ) and
        keep_tags.tag_sets_id = delete_tags.tag_sets_id and
        delete_tags.tags_id not in ( $tags_ids_list ) and
        stm.tags_id = delete_tags.tags_id and
        stm.$table_id_name = ?
END
    }
}

# add tags from the $story_tags list in the form '<id>,<tag_set>:<tag>'
# to the given story or sentence.  if $c->req->param( 'clear_tags' ) is true,
# for each combination of id and tag_set, clear all tags not
# assigned in this request
sub _add_tags
{
    my ( $self, $c, $story_tags ) = @_;

    my $clear_tags_map = {};

    my $tags_map_table = $self->get_table_name() . '_tags_map';
    my $table_id_name  = $self->get_table_name() . '_id';

    # DRL 3/18/2015 this is a hack to make sure that triggers are enabled so that changes reach solr
    # This is needed because we use connection pooling in production and db connections with triggers disabled are reused
    # We;re also explicitly enabling story triggers when the database is created, which should be enough but isn't
    $c->dbis->query( "SELECT enable_story_triggers() " );

    foreach my $story_tag ( @$story_tags )
    {
        # say STDERR "story_tag $story_tag";

        my ( $id, $tag ) = split ',', $story_tag;

        my $tags_id = $self->_get_tags_id( $c, $tag );

        $self->_die_unless_user_can_apply_tag_set_tags( $c, $tags_id );

        # say STDERR "$id, $tags_id";

        my $query = <<END;
INSERT INTO $tags_map_table ( $table_id_name, tags_id) 
    select \$1, \$2
        where not exists (
            select 1 
                from $tags_map_table 
                where $table_id_name = \$1 and
                    tags_id = \$2
        )
END

        # say STDERR $query;

        $c->dbis->query( $query, $id, $tags_id );

        push( @{ $clear_tags_map->{ $id } }, $tags_id );
    }

    if ( $c->req->params->{ clear_tags } )
    {
        $self->_clear_tags( $c, $clear_tags_map );
    }
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
