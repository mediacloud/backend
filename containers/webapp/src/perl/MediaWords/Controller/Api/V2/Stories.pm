package MediaWords::Controller::Api::V2::Stories;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use HTTP::Status qw(:constants);
use Readonly;
use Encode;

use MediaWords::Annotator::Store;
use MediaWords::DBI::Stories;
use MediaWords::Solr;
use MediaWords::Util::ParseJSON;

=head1 NAME

MediaWords::Controller::Stories - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::StoriesBase' }

__PACKAGE__->config(
    action => {
        single    => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        list      => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        put_tags  => { Does => [ qw( ~StoriesEditAuthenticated ~Throttled ~Logged ) ] },
        update    => { Does => [ qw( ~StoriesEditAuthenticated ~Throttled ~Logged ) ] },
        cliff     => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        nytlabels => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub single_GET
{
    my ( $self, $c, $id ) = @_;

    shift;    # to get rid of $self

    $self->{ show_sentences } = $c->req->params->{ sentences };
    $self->{ show_text }      = $c->req->params->{ text };

    $self->SUPER::single_GET( @_ );
}

sub put_tags : Local : ActionClass('MC_REST')
{
}

sub put_tags_PUT
{
    my ( $self, $c ) = @_;

    my $story_tag = $c->req->params->{ 'story_tag' };

    # legacy support for story_tag= param
    if ( $story_tag )
    {
        my $story_tags = ( ref $story_tag ) ? $story_tag : [ $story_tag ];

        $self->_add_tags( $c, $story_tags );

        $self->status_ok( $c, entity => $story_tags );
    }
    else
    {
        $self->process_put_tags( $c );

        $self->status_ok( $c, entity => { success => 1 } );
    }

    return;
}

sub cliff : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $stories_ids = $c->req->params->{ stories_id };
    unless ( $stories_ids )
    {
        die "One or more 'stories_id' is required.";
    }

    $stories_ids = [ $stories_ids ] unless ( ref( $stories_ids ) );

    my $json_list = {};
    for my $stories_id ( @{ $stories_ids } )
    {
        $stories_id = int( $stories_id );

        next if ( $json_list->{ $stories_id } );

        my $annotation;

        my $story = $db->find_by_id( 'stories', $stories_id );
        if ( !$story )
        {
            # mostly useful for testing this end point without triggering a fatal error because CLIFF is not enabled
            $annotation = 'story does not exist';
        }
        else
        {
            my $cliff_store = MediaWords::Annotator::Store->new('cliff_annotations');
            eval { $annotation = $cliff_store->fetch_annotation_for_story( $db, $stories_id ); };
            $annotation ||= 'story is not annotated';
        }

        $json_list->{ $stories_id } = $annotation;

    }

    my $json_items = [];
    for my $stories_id ( keys( %{ $json_list } ) )
    {
        my $json_item = {
            stories_id => $stories_id + 0,
            cliff      => $json_list->{ $stories_id },
        };
        push( @{ $json_items }, $json_item );
    }

    Readonly my $json_pretty => 1;
    my $json = MediaWords::Util::ParseJSON::encode_json( $json_items, $json_pretty );

    # Catalyst expects bytes
    $json = encode_utf8( $json );

    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->content_length( bytes::length( $json ) );
    $c->response->body( $json );
}

sub nytlabels : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $stories_ids = $c->req->params->{ stories_id };
    unless ( $stories_ids )
    {
        die "One or more 'stories_id' is required.";
    }

    $stories_ids = [ $stories_ids ] unless ( ref( $stories_ids ) );

    my $json_list = {};
    for my $stories_id ( @{ $stories_ids } )
    {
        $stories_id = int( $stories_id );

        next if ( $json_list->{ $stories_id } );

        my $annotation;

        my $story = $db->find_by_id( 'stories', $stories_id );
        if ( !$story )
        {
            # mostly useful for testing this end point without triggering a fatal error because NYTLabels is not enabled
            $annotation = 'story does not exist';
        }
        else
        {
            my $nytlabels_store = MediaWords::Annotator::Store->new('nytlabels_annotations');
            eval { $annotation = $nytlabels_store->fetch_annotation_for_story( $db, $stories_id ) };
            $annotation ||= 'story is not annotated';
        }

        $json_list->{ $stories_id } = $annotation;

    }

    my $json_items = [];
    for my $stories_id ( keys( %{ $json_list } ) )
    {
        my $json_item = {
            stories_id => $stories_id + 0,
            nytlabels  => $json_list->{ $stories_id },
        };
        push( @{ $json_items }, $json_item );
    }

    Readonly my $json_pretty => 1;
    my $json = MediaWords::Util::ParseJSON::encode_json( $json_items, $json_pretty );

    # Catalyst expects bytes
    $json = encode_utf8( $json );

    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->content_length( bytes::length( $json ) );
    $c->response->body( $json );
}

sub update : Local : ActionClass('MC_REST')
{
}

# update a single story
sub update_PUT
{
    my ( $self, $c ) = @_;

    my $data = $c->req->data;

    die( "input must be a hash" ) unless ( ref( $data ) eq ref( {} ) );

    die( "input must include stories_id" ) unless ( $data->{ stories_id } );

    my $db = $c->dbis;

    my $story = $db->require_by_id( 'stories', $data->{ stories_id } );

    my $confirm_date = $data->{ confirm_date };
    my $undateable   = $data->{ undateable };

    my $fields = [ qw/title publish_date language url guid description/ ];
    my $update = {};
    map { $update->{ $_ } = $data->{ $_ } if ( defined( $data->{ $_ } ) ) } @{ $fields };

    $db->update_by_id( 'stories', $data->{ stories_id }, $update );

    if ( $confirm_date )
    {
        MediaWords::DBI::Stories::GuessDate::confirm_date( $db, $story );
    }
    else
    {
        MediaWords::DBI::Stories::GuessDate::unconfirm_date( $db, $story );
    }

    MediaWords::DBI::Stories::GuessDate::mark_undateable( $db, $story, $undateable );

    $self->status_ok( $c, entity => { success => 1 } );

}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
