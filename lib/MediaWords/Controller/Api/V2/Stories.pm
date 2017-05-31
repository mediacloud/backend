package MediaWords::Controller::Api::V2::Stories;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use HTTP::Status qw(:constants);
use Readonly;
use Encode;

use MediaWords::DBI::Stories;
use MediaWords::Solr;
use MediaWords::Util::Bitly;
use MediaWords::Util::Bitly::API;
use MediaWords::Util::JSON;

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
        single             => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        list               => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        put_tags           => { Does => [ qw( ~StoriesEditAuthenticated ~Throttled ~Logged ) ] },
        fetch_bitly_clicks => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        corenlp            => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
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

sub corenlp : Local
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
        next if ( $json_list->{ $stories_id } );

        my $json;

        my $story = $db->find_by_id( 'stories', $stories_id );
        if ( !$story )
        {
            # mostly useful for testing this end point without triggering a fatal error because CoreNLP is not enabled
            $json = '"story does not exist"';
        }
        else
        {
            eval { $json = MediaWords::Util::CoreNLP::fetch_annotation_json_for_story( $db, $stories_id ) };
            $json ||= '"story is not annotated"';
        }

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

    # Response might contain multibyte characters
    $json = encode( 'utf-8', $json );

    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->content_length( bytes::length( $json ) );
    $c->response->body( $json );
}

sub fetch_bitly_clicks : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $stories_id      = $c->req->params->{ stories_id } + 0;
    my $stories_url     = $c->req->params->{ url };
    my $start_timestamp = $c->req->params->{ start_timestamp };
    my $end_timestamp   = $c->req->params->{ end_timestamp };

    unless ( $stories_id xor $stories_url )
    {
        die "Either the story ID ('stories_id') or URL ('url') should be set.";
    }
    unless ( $start_timestamp and $end_timestamp )
    {
        die "Both 'start_timestamp' and 'end_timestamp' should be set.";
    }

    my $http_status = HTTP_OK;
    my $response    = {};
    if ( $stories_id )
    {
        $response->{ stories_id } = $stories_id;
        my $story = $db->find_by_id( 'stories', $stories_id );
        if ( !$story )
        {
            $self->status_bad_request( $c, message => "stories_id '$stories_id' does not exist" );
            return;
        }
    }
    elsif ( $stories_url )
    {
        $response->{ url } = $stories_url;
    }

    my ( $bitly_clicks, $total_click_count );
    eval {

        my ( $agg_stories_id, $agg_stories_url );

        if ( $stories_id )
        {

            my $story = $db->find_by_id( 'stories', $stories_id );
            unless ( $story )
            {
                die "Unable to find story $stories_id.";
            }

            $bitly_clicks =
              MediaWords::Util::Bitly::fetch_stats_for_story( $db, $stories_id, $start_timestamp, $end_timestamp );

            ( $agg_stories_id, $agg_stories_url ) = ( $stories_id, $story->{ url } );

        }
        elsif ( $stories_url )
        {

            $bitly_clicks =
              MediaWords::Util::Bitly::API::fetch_stats_for_url( $db, $stories_url, $start_timestamp, $end_timestamp );

            ( $agg_stories_id, $agg_stories_url ) = ( 0, $stories_url );

        }

        # die() on non-fatal errors so that eval{} could catch them
        if ( $bitly_clicks->{ error } )
        {
            die $bitly_clicks->{ error };
        }

        # Aggregate stats and come up with a total click count for both
        # convenience and the reason that the count could be different
        # (e.g. because of homepage redirects being skipped)
        my $stats = MediaWords::Util::Bitly::aggregate_story_stats( $agg_stories_id, $agg_stories_url, $bitly_clicks );
        $total_click_count = $stats->total_click_count();
    };
    unless ( $@ )
    {
        $response->{ bitly_clicks }      = $bitly_clicks;
        $response->{ total_click_count } = $total_click_count;
    }
    else
    {
        my $error_message = $@;
        $response->{ error } = $error_message;

        if ( MediaWords::Util::Bitly::API::error_is_rate_limit_exceeded( $error_message ) )
        {
            $http_status = HTTP_TOO_MANY_REQUESTS;

        }
        elsif ( $error_message =~ /NOT_FOUND/i )
        {
            $http_status = HTTP_NOT_FOUND;

        }
        else
        {
            $http_status = HTTP_INTERNAL_SERVER_ERROR;
        }
    }

    Readonly my $json_pretty => 1;
    Readonly my $json_utf8   => 1;
    my $json = MediaWords::Util::JSON::encode_json( $response, $json_pretty, $json_utf8 );

    $c->response->status( $http_status );
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
