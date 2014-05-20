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

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub _purge_extra_fields :
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

sub default_output_fields
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

    return $items;
}

sub single : Local : ActionClass('REST') : Does('~ApiKeyAuthenticated') : Does('~Throttled') : Does('~Logged')
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

sub _fetch_list
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    my $list;

    if ( $self->list_api_requires_filter_field() )
    {
        my $query_filter_field_name = $self->list_query_filter_field();

        my $filter_field_value = $c->req->param( $query_filter_field_name );

        if ( !defined( $filter_field_value ) )
        {
            die "Missing required param $query_filter_field_name";
        }

        my $query =
          "select * from $table_name where $id_field > ? and $query_filter_field_name = ? ORDER by $id_field asc limit ? ";

        $list = $c->dbis->query( $query, $last_id, $filter_field_value, $rows )->hashes;
    }
    else
    {
        my $query = "select * from $table_name where $id_field > ? ORDER by $id_field asc limit ? ";

        $list = $c->dbis->query( $query, $last_id, $rows )->hashes;
    }

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

sub list : Local : ActionClass('REST') : Does('~ApiKeyAuthenticated') : Does('~Throttled') : Does('~Logged')
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

    Readonly my $query => "SELECT tag_sets.name from tags natural join tag_sets where tags_id = ? limit 1 ";

    my $tag_set = $c->dbis->query( $query, $tags_id )->hashes->[ 0 ]->{ name };

    die "Illegal tag_set name '$tag_set', tag_set must be user email "
      unless $c->stash->{ auth_user }->{ email } eq $tag_set;
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

        my ( $tag_set, $tag_name ) = split ':', $tag_string;

        die "Illegal tag_set name '$tag_set', tag_set must be user email "
          unless $c->stash->{ auth_user }->{ email } eq $tag_set;

        my $tag_sets = $c->dbis->query( "SELECT * from tag_sets where name = ?", $tag_set )->hashes;

        if ( !scalar( @$tag_sets ) > 0 )
        {
            $tag_sets = [ $c->dbis->create( 'tag_sets', { 'name' => $tag_set } ) ];
        }

        die "invalid tag set " unless scalar( @$tag_sets ) > 0;

        # say STDERR "tag_sets";
        # say STDERR Dumper( $tag_sets );

        my $tag_sets_id = $tag_sets->[ 0 ]->{ tag_sets_id };

        my $tags =
          $c->dbis->query( "SELECT * from tags where tag_sets_id = ? and tag = ? ", $tag_sets_id, $tag_name )->hashes;

        # say STDERR Dumper( $tags );

        my $tag;

        if ( !scalar( @$tags ) )
        {
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

sub _add_tags
{
    my ( $self, $c, $story_tags ) = @_;

    foreach my $story_tag ( @$story_tags )
    {
        # say STDERR "story_tag $story_tag";

        my ( $id, $tag ) = split ',', $story_tag;

        my $tags_id = $self->_get_tags_id( $c, $tag );

        $self->_die_unless_tag_set_matches_user_email( $c, $tags_id );

        # say STDERR "$id, $tags_id";

        my $tags_map_table = $self->get_table_name() . '_tags_map';
        my $table_id_name  = $self->get_table_name() . '_id';

        my $query = "INSERT INTO $tags_map_table ( $table_id_name, tags_id) VALUES (?, ? )";

        # say STDERR $query;

        $c->dbis->query( $query, $id, $tags_id );
    }
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
