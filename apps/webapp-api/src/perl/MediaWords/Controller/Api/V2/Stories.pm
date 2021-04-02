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

use MediaWords::DBI::Stories;
use MediaWords::Solr;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::Web::UserAgent;
use MediaWords::Util::Web::UserAgent::Request;

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

sub _cliff_annotator_request($)
{
    my $text = shift;

    my $url = 'http://cliff-annotator:8080/cliff/parse/text';
    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
    $request->set_content_type( 'application/x-www-form-urlencoded; charset=utf-8' );
    $request->set_content( {'q' => $text } );

    return $request;
}

sub _nytlabels_annotator_request($)
{
    my $text = shift;

    my $url = 'http://nytlabels-annotator:8080/predict.json';
    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
    $request->set_content_type( 'application/json; charset=utf-8' );
    $request->set_content( MediaWords::Util::ParseJSON::encode_json( {'text' => $text}) );

    return $request;
}

# FIXME once the API gets rewritten to Python (any day now!), make it reuse
# same code that calls annotator from extractor instead of this awful hack
sub _annotate_story_ids($$$$)
{
    my ( $db, $stories_ids, $results_key, $request_generator_subref ) = @_;

    unless ( ref( $request_generator_subref ) eq ref( sub {} )) {
        LOGDIE "Request generator is not a subref";
    }

    $stories_ids = [ $stories_ids ] unless ( ref( $stories_ids ) );

    DEBUG "Annotating " . scalar(@{ $stories_ids }) . " stories...";
    my $json_list = {};
    for my $stories_id ( @{ $stories_ids } )
    {
        $stories_id = int( $stories_id );

        next if ( $json_list->{ $stories_id } );

        DEBUG "Fetching story $stories_id...";
        my $story = $db->find_by_id( 'stories', $stories_id );
        unless ( $story ) {
            $json_list->{ $stories_id } = 'story does not exist';
            next;
        }

        unless ( $story->{ language } eq 'en' or ( ! defined $story->language )) {
            $json_list->{ $stories_id } = 'story is not in English';
            next;
        }

        DEBUG "Fetching concatenated sentences for story $stories_id...";
        my ( $full_text ) = $db->query( <<SQL,
            SELECT string_agg(sentence, ' ' ORDER BY sentence_number)
            FROM story_sentences
            WHERE stories_id = ?
SQL
            $story->{ stories_id }
        )->flat();
        unless ( $full_text ) {
            $json_list->{ $stories_id } = 'story does not have any sentences';
            next;
        }

        DEBUG "Annotating story $stories_id...";
        my $request = $request_generator_subref->( $full_text );

        my $ua = MediaWords::Util::Web::UserAgent->new();
        $ua->set_timing( [1, 2, 4, 8] );
        $ua->set_timeout( 60 * 10 );
        $ua->set_max_size( undef );

        my $response = $ua->request( $request );

        unless ( $response->is_success() ) {
            ERROR "Fetching annotation for story $stories_id failed: " . $response->decoded_content();
            $json_list->{ $stories_id } = 'annotating failed';
            next;
        }

        my $annotation = MediaWords::Util::ParseJSON::decode_json( $response->decoded_content() );

        $json_list->{ $stories_id } = $annotation;
    }

    my $json_items = [];

    # Iterate over original list of story ID parameters to preserve order
    for my $stories_id ( @{ $stories_ids } )
    {
        my $json_item = {
            stories_id   => $stories_id + 0,
            $results_key => $json_list->{ $stories_id },
        };
        push( @{ $json_items }, $json_item );
    }

    Readonly my $json_pretty => 1;
    my $json = MediaWords::Util::ParseJSON::encode_json( $json_items, $json_pretty );

    # Catalyst expects bytes
    $json = encode_utf8( $json );

    return $json;
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

    my $json = _annotate_story_ids( $db, $stories_ids, 'cliff', \&_cliff_annotator_request );

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

    my $json = _annotate_story_ids( $db, $stories_ids, 'nytlabels', \&_nytlabels_annotator_request );

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
