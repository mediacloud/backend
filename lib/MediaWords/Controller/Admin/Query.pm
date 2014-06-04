package MediaWords::Controller::Admin::Query;

use strict;
use warnings;

use base 'Catalyst::Controller';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use JSON;

use MediaWords::Solr;

sub sentences : Local : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $q     = $c->req->parameters->{ 'q' };
    my $fq    = $c->req->parameters->{ 'fq' };
    my $start = $c->req->parameters->{ 'start' };
    my $rows  = $c->req->parameters->{ 'rows' };

    $start //= 0;
    $rows  //= 1000;

    my $solr_params = { q => $q, fq => $fq, start => $start, rows => $rows };

    my $json = MediaWords::Solr::query_encoded_json( $solr_params, $c );

    $c->res->header( 'Content-Length', bytes::length( $json ) );
    $c->res->content_type( 'application/json; charset=UTF-8' );
    $c->res->body( $json );
}

sub wc : Local : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $q  = $c->req->parameters->{ 'q' };
    my $fq = $c->req->parameters->{ 'fq' };

    my $words = MediaWords::Solr::count_words( $q, $fq, [ 'en' ] );

    my $json = JSON::encode_json( $words );

    $c->res->header( 'Content-Length', bytes::length( $json ) );
    $c->res->content_type( 'application/json; charset=UTF-8' );
    $c->res->body( $json );
}

1;
