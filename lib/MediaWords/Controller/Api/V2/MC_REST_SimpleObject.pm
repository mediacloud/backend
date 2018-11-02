
package MediaWords::Controller::Api::V2::MC_REST_SimpleObject;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller::REST';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Readonly;

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
        single => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
        list   => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },    #
      }    #
);         #

Readonly my $ROWS_PER_PAGE => 20;

sub _purge_extra_fields
{
    my ( $self, $c, $obj ) = @_;

    my $new_obj = {};

    foreach my $default_output_field ( @{ $self->default_output_fields( $c ) } )
    {
        $new_obj->{ $default_output_field } = $obj->{ $default_output_field };
    }

    return $new_obj;
}

sub _purge_extra_fields_obj_list
{
    my ( $self, $c, $list ) = @_;

    return [ map { $self->_purge_extra_fields( $c, $_ ) } @{ $list } ];
}

sub _purge_non_permissible_fields
{
    my ( $self, $obj ) = @_;

    my $new_obj = {};
    for my $field ( @{ $self->permissible_output_fields } )
    {
        $new_obj->{ $field } = $obj->{ $field };
    }

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

    if ( $self->default_output_fields( $c ) && !$all_fields )
    {
        $items = $self->_purge_extra_fields_obj_list( $c, $items );
    }

    if ( $self->has_extra_data() )
    {
        $items = $self->add_extra_data( $c, $items );
    }

    if ( $self->has_nested_data() )
    {
        my $nested_data = int( $c->req->param( 'nested_data' ) // 1 );

        if ( $nested_data )
        {
            $items = $self->_add_nested_data( $c->dbis, $items );
        }
    }

    if ( $self->permissible_output_fields() )
    {
        $items = $self->_purge_non_permissible_fields_obj_list( $items );
    }

    return $items;
}

sub single : Local : ActionClass('MC_REST')    # action roles are to be set for each derivative sub-actions
{
}

sub single_GET
{
    my ( $self, $c, $id ) = @_;

    my $table_name = $self->get_table_name();

    # ID is typically an int, e.g. media_id or stories_id
    $id = int( $id );
    unless ( $id < 1 )
    {
        die "ID must be positive.";
    }

    my $id_field = $table_name . "_id";

    my $query = "select * from $table_name where $id_field = ? ";

    my $all_fields = int( $c->req->param( 'all_fields' ) // 0 );

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

    my $q_name_val = $c->dbis->quote( '%' . $name_val . '%' );

    return "and $name_field ilike $q_name_val";
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

        push( @{ $clauses }, "$required_field_name = " . $c->dbis->quote( $val ) );
    }

    my $field_names = $self->list_optional_query_filter_field || [];
    $field_names = ref( $field_names ) ? $field_names : [ $field_names ];
    for my $field_name ( @{ $field_names } )
    {
        my $val = $c->req->params->{ $field_name };

        if ( $val )
        {
            push( @{ $clauses }, "$field_name = " . $c->dbis->quote( $val ) );
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

sub _fetch_list($$$$$$)
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    my $list;

    $last_id = int( $last_id );

    my $name_clause         = $self->get_name_search_clause( $c );
    my $filter_field_clause = $self->_get_filter_field_clause( $c );
    my $extra_where_clause  = $self->get_extra_where_clause( $c );
    my $order_by_clause     = $self->order_by_clause( $c ) || "$id_field ASC";

    my $query = <<"SQL";
        SELECT *
        FROM $table_name
        WHERE
            $id_field > ?
            $name_clause
            $extra_where_clause
            $filter_field_clause
        ORDER BY $order_by_clause
        LIMIT ?
SQL

    $list = $c->dbis->query( $query, $last_id, $rows )->hashes;

    my $num_rows = scalar( @{ $list } );

    TRACE( "fetch_list last_id $last_id got $num_rows rows: $query" );

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

sub list : Local : ActionClass('MC_REST')    # action roles are to be set for each derivative sub-actions
{
}

sub list_GET
{
    my ( $self, $c ) = @_;

    # TRACE "starting list_GET";

    my $table_name = $self->get_table_name();

    my $id_field = $table_name . "_id";

    my $last_id_param_name = $self->_get_list_last_id_param_name( $c );

    my $last_id = int( $c->req->param( $last_id_param_name ) // 0 );
    $last_id //= 0;

    # TRACE "last_id: $last_id";

    my $all_fields = $c->req->param( 'all_fields' );
    $all_fields //= 0;

    my $rows = int( $c->req->param( 'rows' ) || $ROWS_PER_PAGE + 0 );
    $rows = List::Util::min( $rows, 1_000 );

    # TRACE "rows $rows";

    my $list = $self->_fetch_list( $c, $last_id, $table_name, $id_field, $rows );

    $list = $self->_process_result_list( $c, $list, $all_fields );

    $self->status_ok( $c, entity => $list );
}

sub _die_unless_tag_set_matches_user_email
{
    my ( $self, $c, $tags_id ) = @_;

    $tags_id = int( $tags_id );

    Readonly my $query =>
      "SELECT tag_sets.name from tags, tag_sets where tags.tag_sets_id = tag_sets.tag_sets_id AND tags_id = ? limit 1 ";

    my $hashes = $c->dbis->query( $query, $tags_id )->hashes();

    #TRACE "Hashes:\n" . Dumper( $hashes );

    my $tag_set = $hashes->[ 0 ]->{ name };

    die "Undefined tag_set for tags_id: $tags_id" unless defined( $tag_set );

    die "Illegal tag_set name '$tag_set', tag_set must be user email "
      unless $c->stash->{ api_auth }->email() eq $tag_set;
}

sub _get_user_tag_set_permissions
{
    my ( $api_auth, $tag_set, $dbis ) = @_;

    my $permissions =
      $dbis->query( "SELECT * from  auth_users_tag_sets_permissions where auth_users_id = ? and tag_sets_id = ? ",
        $api_auth->user_id(), $tag_set->{ tag_sets_id } )->hashes()->[ 0 ];

    return $permissions;
}

#tag_set permissions apply_tags, create_tags, edit_tag_set_descriptors, edit_tag_descriptors

sub _die_unless_user_can_apply_tag_set_tags
{
    my ( $self, $c, $tag_set ) = @_;

    return if $c->stash->{ api_auth }->email() eq $tag_set->{ name };

    my $permissions = _get_user_tag_set_permissions( $c->stash->{ api_auth }, $tag_set, $c->dbis );

    #TRACE Dumper( $permissions );

    die "user does not have apply tag set tags permissions" unless defined( $permissions ) && $permissions->{ apply_tags };
}

sub _die_unless_user_can_create_tag_set_tags
{
    my ( $self, $c, $tag_set ) = @_;

    return if $c->stash->{ api_auth }->email() eq $tag_set->{ name };

    my $permissions = _get_user_tag_set_permissions( $c->stash->{ api_auth }, $tag_set, $c->dbis );

    #TRACE Dumper( $permissions );

    die "user does not have create tag permissions for tag set"
      unless defined( $permissions ) && $permissions->{ create_tags };
}

sub die_unless_user_can_edit_tag_set_descriptors
{
    my ( $self, $c, $tag_set ) = @_;

    return if $c->stash->{ api_auth }->email() eq $tag_set->{ name };

    my $permissions = _get_user_tag_set_permissions( $c->stash->{ api_auth }, $tag_set, $c->dbis );

    #TRACE Dumper( $permissions );

    die "User " . $c->stash->{ api_auth }->email() .
      " doesn't have permission to edit tag set descriptors for tag set id " . $tag_set->{ tag_sets_id }
      unless defined( $permissions ) && $permissions->{ edit_tag_set_descriptors };
}

sub die_unless_user_can_edit_tag_set_tag_descriptors
{
    my ( $self, $c, $tag_set ) = @_;

    return if $c->stash->{ api_auth }->email() eq $tag_set->{ name };

    my $permissions = _get_user_tag_set_permissions( $c->stash->{ api_auth }, $tag_set, $c->dbis );

    #TRACE Dumper( $permissions );

    die "User " . $c->stash->{ api_auth }->email() .
      " doesn't have permission to edit tag descriptors in tag set id " . $tag_set->{ tag_sets_id }
      unless defined( $permissions ) && $permissions->{ edit_tag_descriptors };
}

sub _get_tags_id
{
    my ( $self, $c, $tag_string ) = @_;

    if ( $tag_string =~ /^\d+/ )
    {
        # TRACE "returning int: $tag_string";
        return int( $tag_string );
    }
    elsif ( $tag_string =~ /^.+:.+$/ )
    {
        # TRACE "processing tag_sets:tag_name";

        my ( $tag_set_name, $tag_name ) = split ':', $tag_string;

        #TRACE Dumper( $c->stash );
        my $user_email = $c->stash->{ api_auth }->email();

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

        # TRACE "tag_sets";
        # TRACE Dumper( $tag_sets );

        my $tag_set     = $tag_sets->[ 0 ];
        my $tag_sets_id = $tag_set->{ tag_sets_id };

        $self->_die_unless_user_can_apply_tag_set_tags( $c, $tag_set );

        my $tags =
          $c->dbis->query( "SELECT * from tags where tag_sets_id = ? and tag = ? ", $tag_sets_id, $tag_name )->hashes;

        # TRACE Dumper( $tags );

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

    my $table_name = $self->get_table_name();

    while ( my ( $id, $tags_ids ) = each( %{ $tags_map } ) )
    {
        my $tags_ids_list = join( ',', @{ $tags_ids } );

        $id = int( $id );

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

    my $table_name = $self->get_table_name();

    foreach my $story_tag ( @$story_tags )
    {
        # TRACE "story_tag $story_tag";

        my ( $id, $tag ) = split ',', $story_tag;

        $id = int( $id );

        my $tags_id = $self->_get_tags_id( $c, $tag );

        my $tag_set = $c->dbis->query(
            " SELECT * from tag_sets where tag_sets_id in ( select tag_sets_id from tags where tags_id = ? ) ", $tags_id )
          ->hashes->[ 0 ];

        $self->_die_unless_user_can_apply_tag_set_tags( $c, $tag_set );

        # TRACE "$id, $tags_id";

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

        # TRACE $query;

        $c->dbis->query( $query, $id, $tags_id );

        push( @{ $clear_tags_map->{ $id } }, $tags_id );
    }

    if ( int( $c->req->params->{ clear_tags } // 0 ) )
    {
        $self->_clear_tags( $c, $clear_tags_map );
    }
}

# process a single recoed in a put_tags request.  see api docs for stories/put_tags.
# returns put_tag object with a 'tag_row' field that points to the hash for the tag edited.
sub _process_single_put_tag($$$)
{
    my ( $self, $c, $put_tag ) = @_;

    my $db        = $c->dbis;
    my $table     = $self->get_table_name;
    my $id_field  = "${ table }_id";
    my $map_table = "${ table }_tags_map";

    die( "input must be a list of records" ) unless ( ref( $put_tag ) eq ref( {} ) );

    die( "each record must include a '$id_field' field" ) unless ( $put_tag->{ $id_field } );

    die( "input must include either a tags_id field or a tag and a tag_set field" )
      unless ( $put_tag->{ tags_id } or ( $put_tag->{ tag } && $put_tag->{ tag_set } ) );

    my $tag =
        $put_tag->{ tags_id }
      ? $db->require_by_id( 'tags', $put_tag->{ tags_id } )
      : MediaWords::Util::Tags::lookup_or_create_tag( $db, "$put_tag->{ tag_set }:$put_tag->{ tag }" );

    die( "unsupported table '$table'" ) unless ( grep { $_ eq $table } qw/stories media story_sentences/ );

    my $action = $put_tag->{ action } || 'add';
    if ( $action eq 'add' )
    {
        $db->query( <<SQL, $put_tag->{ $id_field }, $tag->{ tags_id } );
insert into $map_table ( $id_field, tags_id )
    select \$1, \$2 where not exists ( select 1 from $map_table where $id_field = \$1 and tags_id = \$2 )
SQL
    }
    elsif ( $action eq 'remove' )
    {
        $db->query( <<SQL, $put_tag->{ $id_field }, $tag->{ tags_id } );
delete from $map_table where $id_field = \$1 and tags_id = \$2
SQL
    }
    else
    {
        die( "Uknown put_tags action: $action" );
    }

    $put_tag->{ tag } = $tag;

    return $put_tag;
}

# process put_tags command for the current table.  see api docs for stories/put_tags.
# JSON format.
sub process_put_tags($$)
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    die( "no JSON input" ) unless ( $data );

    die( "json must be a list" ) unless ( ref( $data ) eq ref( [] ) );

    $c->dbis->begin;

    my $put_tags = [ map { $self->_process_single_put_tag( $c, $_ ) } @{ $data } ];

    if ( int( $c->req->params->{ clear_tag_sets } // 0 ) )
    {
        my $id_field       = $self->get_table_name . "_id";
        my $clear_tags_map = {};
        for my $put_tag ( @{ $put_tags } )
        {
            next unless ( !$_->{ action } || ( $_->{ action } eq 'add' ) );
            push( @{ $clear_tags_map->{ $put_tag->{ $id_field } } }, $put_tag->{ tag }->{ tags_id } );
        }

        $self->_clear_tags( $c, $clear_tags_map );
    }
    $c->dbis->commit;
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
