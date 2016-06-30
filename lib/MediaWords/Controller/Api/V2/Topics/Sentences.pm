package MediaWords::Controller::Api::V2::Topics::Sentences;
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use Data::Dumper;
use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;
use MediaWords::Solr;
use MediaWords::CM::Dump;
use MediaWords::CM;
use MediaWords::Controller::Api::V2::Sentences;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { count_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topic_id ) = @_;
    $c->stash->{ topic_id } = $topic_id;
}

sub sentences : Chained('apibase') : PathPart('sentences') : CaptureArgs(0)
{

}

sub count : Chained('sentences') : Args(0) : ActionClass('REST')
{

}

sub count_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $cdts = MediaWords::CM::require_time_slice_for_controversy(
        $c->dbis,
        $c->stash->{ topic_id },
        $c->req->params->{ timeslice },
        $c->req->params->{ snapshot }
    );

    my $q = $c->req->params->{ q };

    my $cdts_clause = "{~ controversy_dump_time_slice:$cdts->{ controversy_dump_time_slices_id } ~}";

    $q = $q ? "$cdts_clause and ( $q )" : $cdts_clause;

    $c->req->params->{ q } = $q;

    $c->req->params->{ split_start_date } ||= substr( $cdts->{ start_date }, 0, 12 );
    $c->req->params->{ split_end_date }   ||= substr( $cdts->{ end_date },   0, 12 );

    return $c->controller( 'Api::V2::Sentences' )->count_GET( $c );
}

1;
