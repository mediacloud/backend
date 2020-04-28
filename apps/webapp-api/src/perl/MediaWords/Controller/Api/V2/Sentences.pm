package MediaWords::Controller::Api::V2::Sentences;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Encode;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use Readonly;

use MediaWords::Solr;
use MediaWords::Util::ParseJSON;
use MediaWords::Solr::Query::MatchingSentences;

Readonly my $DEFAULT_ROW_COUNT => 1000;
Readonly my $MAX_ROW_COUNT     => 10_000;

=head1 NAME

MediaWords::Controller::Media - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config(
    action => {
        single      => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        list        => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        count       => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        field_count => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub get_table_name
{
    return "story_sentences";
}

sub list : Local : ActionClass('MC_REST')
{
    #TRACE "starting Sentences/list";
}

# return the solr sort param corresponding with the possible
# api params values of publish_date_asc, publish_date_desc, and random
sub _get_sort_param
{
    my ( $sort ) = @_;

    $sort //= 'publish_date_asc';

    $sort = lc( $sort );

    if ( $sort eq 'publish_date_asc' )
    {
        return 'publish_date asc';
    }
    elsif ( $sort eq 'publish_date_desc' )
    {
        return 'publish_date desc';
    }
    elsif ( $sort eq 'random' )
    {
        return 'random_1 asc';
    }
    else
    {
        die( "Unknown sort: $sort" );
    }
}

sub list_GET
{
    my ( $self, $c ) = @_;

    # TRACE "starting list_GET";

    my $params = {};

    my $q  = $c->req->params->{ 'q' };
    my $fq = $c->req->params->{ 'fq' };

    my $start = int( $c->req->params->{ 'start' } // 0 );
    my $rows  = int( $c->req->params->{ 'rows' }  // $DEFAULT_ROW_COUNT + 0 );
    my $sort  = $c->req->params->{ 'sort' };

    $params->{ q }     = $q;
    $params->{ fq }    = $fq;
    $params->{ start } = $start;
    $params->{ rows }  = $rows;

    $params->{ sort } = _get_sort_param( $sort ) if ( $rows );

    $rows = List::Util::min( $rows, $MAX_ROW_COUNT + 0 );

    my $sentences = MediaWords::Solr::Query::MatchingSentences::query_matching_sentences( $c->dbis, $params );

    # stories are random but sentences are in stories_id, sentence_number order
    if ( $sort && ( $sort eq 'random' ) )
    {
        $sentences = [ List::Util::shuffle( @{ $sentences } ) ];
    }

    MediaWords::Util::ParseJSON::numify_fields( $sentences, [ qw/stories_id story_sentences_id/ ] );

    Readonly my $json_pretty => 0;
    my $json = MediaWords::Util::ParseJSON::encode_json( $sentences, $json_pretty );

    # Catalyst expects bytes
    $json = encode_utf8( $json );

    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->content_length( bytes::length( $json ) );
    $c->response->body( $json );
}

sub count : Local : ActionClass('MC_REST')
{
}

sub count_GET
{
    my ( $self, $c ) = @_;

    die( "The sentences/count call has been removed.  Use stories/count or sentences/list instead." );
}

sub field_count : Local : ActionClass('MC_REST')
{
}

sub field_count_GET
{
    my ( $self, $c ) = @_;

    die( "The sentences/field_count call has been removed. Use stories/tag_count or sentences/list instead." );
}

# override
sub single_GET
{
    die( "not implemented" );
}

1;
