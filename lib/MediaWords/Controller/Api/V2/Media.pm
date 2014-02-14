package MediaWords::Controller::Api::V2::Media;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;

use strict;
use warnings;
use base 'Catalyst::Controller';
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

sub _add_data_to_media
{

    my ( $self, $db, $media ) = @_;

    foreach my $media_source ( @{ $media } )
    {
        say STDERR "adding media_source tags ";
        my $media_source_tags = $db->query(
"select tags.tags_id, tags.tag, tag_sets.tag_sets_id, tag_sets.name as tag_set from media_tags_map natural join tags natural join tag_sets where media_id = ? ORDER by tags_id",
            $media_source->{ media_id }
        )->hashes;
        $media_source->{ media_source_tags } = $media_source_tags;
    }

    foreach my $media_source ( @{ $media } )
    {
        say STDERR "adding media_sets ";
        my $media_source_tags = $db->query(
"select media_sets.media_sets_id, media_sets.name, media_sets.description, media_sets.set_type from media_sets_media_map natural join media_sets where media_id = ? ORDER by media_sets_id",
            $media_source->{ media_id }
        )->hashes;
        $media_source->{ media_sets } = $media_source_tags;
    }

    return $media;

}

## TODO move these to a centralized location instead of copying them in every API class 
#A list top level object fields to include by default in API results unless all_fields is true
Readonly my $default_output_fields => [ qw ( name url media_id ) ];
sub _purge_extra_fields:
{
    my ( $self, $obj ) = @_;

    my $new_obj = {};

    foreach my $default_output_field ( @ {$default_output_fields } )
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

sub single : Local : ActionClass('REST')
{
}

sub single_GET : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $query = "select s.* from media s where media_id = ? ";

    my $media = $c->dbis->query( $query, $media_id )->hashes();

    my $all_fields = $c->req->param( 'all_fields' );
    $all_fields   //= 0;

    if ( ! $all_fields )
    {
	$media = $self->_purge_extra_fields_obj_list( $media );
    }


    $self->_add_data_to_media( $c->dbis, $media );

    $self->status_ok( $c, entity => $media );
}

sub list : Local : ActionClass('REST')
{
}

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    say STDERR "starting list_GET";

    my $last_media_id = $c->req->param( 'last_media_id' );
    say STDERR "last_media_id: $last_media_id";

    $last_media_id //= 0;

    my $all_fields = $c->req->param( 'all_fields' );
    $all_fields   //= 0;

    my $rows =  $c->req->param( 'rows' );
    say STDERR "rows $rows";

    $rows //= ROWS_PER_PAGE;


    my $media = $c->dbis->query( "select s.* from media s where media_id > ? ORDER by media_id asc limit ?",
        $last_media_id, $rows )->hashes;

    if ( ! $all_fields )
    {
	say STDERR "Purging extra fields in";
	say STDERR Dumper( $media );
	$media = $self->_purge_extra_fields_obj_list( $media );
	say STDERR "Purging result:";
	say STDERR Dumper( $media );
    }

    $self->_add_data_to_media( $c->dbis, $media );

    $self->status_ok( $c, entity => $media );
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
