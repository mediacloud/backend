package MediaWords::Controller::Api::V2::Sentences;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Date::Calc;
use Encode;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use JSON::PP;
use List::Compare;

use MediaWords::Solr;
use MediaWords::Util::ParseJSON;

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

# fill stories_ids temporary table with stories_ids from the given sentences
# and return the temp table name
sub _get_stories_ids_temporary_table
{
    my ( $db, $sentences ) = @_;

    my $table_name = '_stories_ids';

    $db->query( "CREATE TEMPORARY TABLE $table_name (stories_id BIGINT)" );

    my $copy_from = $db->copy_from( "COPY $table_name FROM STDIN" );
    for my $ss ( @{ $sentences } )
    {
        $copy_from->put_line( $ss->{ stories_id } . '' );
    }
    $copy_from->end();

    return $table_name;
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

# given the raw data structure returned by the solr query to sentences/list, return the entity that should be passed
# back to the client for the sentences/list end point.  this is mostly just mirroring the solr data structure, but
# we include it so that we don't pass extra fields that may pop up in the solr query over time as we change sorl versions
# and schemas.
sub _get_sentences_entity_from_json_data
{
    my ( $data ) = @_;

    my $entity = {};

    map { $entity->{ responseHeader }->{ params }->{ $_ } = $data->{ responseHeader }->{ params }->{ $_ } }
      qw/sort df wt q fq rows start/;

    map { $entity->{ responseHeader }->{ $_ } = $data->{ responseHeader }->{ $_ } } qw/status QTime/;

    for my $data_doc ( @{ $data->{ response }->{ docs } } )
    {
        my $entity_doc = {};

        map { $entity_doc->{ $_ } = $data_doc->{ $_ } }
          qw/sentence media_id publish_date sentence_number stories_id story_sentences_id _version_/;

        push( @{ $entity->{ response }->{ docs } }, $entity_doc );
    }

    return $entity;
}

sub list_GET
{
    my ( $self, $c ) = @_;

    # TRACE "starting list_GET";

    my $params = {};

    my $q  = $c->req->params->{ 'q' };
    my $fq = $c->req->params->{ 'fq' };

    my $start = int( $c->req->params->{ 'start' } // 0 );
    my $rows  = int( $c->req->params->{ 'rows' }  // 0 );
    my $sort  = $c->req->params->{ 'sort' };

    $rows  //= 1000;
    $start //= 0;

    $params->{ q }     = $q;
    $params->{ fq }    = $fq;
    $params->{ start } = $start;
    $params->{ rows }  = $rows;

    $params->{ sort } = _get_sort_param( $sort ) if ( $rows );

    $rows = List::Util::min( $rows, 10000 );

    my $sentences = MediaWords::Solr::query_matching_sentences( $c->dbis, $params );

    # stories are random but sentences are in stories_id, sentence_number order
    if ( $sort && ( $sort eq 'random' ) )
    {
        $sentences = [ List::Util::shuffle( @{ $sentences } ) ];
    }

    MediaWords::Util::ParseJSON::numify_fields( $sentences, [ qw/stories_id story_sentences_id/ ] );

    #this uses inline python json, which is very slow for large objects
    #$self->status_ok( $c, entity => $sentences );
    #
    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->body( encode_utf8( JSON::PP::encode_json( $sentences ) ) );
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
