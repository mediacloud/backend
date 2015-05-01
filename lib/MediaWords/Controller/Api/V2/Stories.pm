package MediaWords::Controller::Api::V2::Stories;
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

use MediaWords::DBI::Stories;
use MediaWords::Solr;

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
        single_GET   => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list_GET     => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        put_tags_PUT => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

use constant ROWS_PER_PAGE => 20;

sub single_GET : Local
{
    my ( $self, $c, $id ) = @_;

    shift;    # to get rid of $self

    $self->{ show_sentences } = $c->req->params->{ sentences };
    $self->{ show_text }      = $c->req->params->{ text };

    $self->SUPER::single_GET( @_ );
}

sub put_tags : Local : ActionClass('REST')
{
}

sub put_tags_PUT : Local
{
    my ( $self, $c ) = @_;

    my $subset = $c->req->data;

    my $story_tag = $c->req->params->{ 'story_tag' };

    my $story_tags;

    if ( ref $story_tag )
    {
        $story_tags = $story_tag;
    }
    else
    {
        $story_tags = [ $story_tag ];
    }

    # say STDERR Dumper( $story_tags );

    $self->_add_tags( $c, $story_tags );

    $self->status_ok( $c, entity => $story_tags );

    return;
}

sub corenlp : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $stories_ids = $c->req->params->{ stories_id };

    $stories_ids = [ $stories_ids ] unless ( ref( $stories_ids ) );

    my $json_list = {};
    for my $stories_id ( @{ $stories_ids } )
    {
        next if ( $json_list->{ $stories_id } );

        my $json;
        eval { $json = MediaWords::Util::CoreNLP::fetch_annotation_json_for_story_and_all_sentences( $db, $stories_id ) };
        $json ||= '"story is not annotated"';

        $json_list->{ $stories_id } = $json;

    }

    my $json_items = [];
    for my $stories_id ( keys( %{ $json_list } ) )
    {
        my $json_item = <<"END";
{ 
  "stories_id": $stories_id,
  "corenlp": $json_list->{ $stories_id }
}
END
        push( @{ $json_items }, $json_item );
    }

    my $json = "[\n" . join( ",\n", @{ $json_items } ) . "\n]\n";

    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->content_length( bytes::length( $json ) );
    $c->response->body( $json );
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
