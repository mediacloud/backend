package MediaWords::Controller::Api::V2::Topics::Sentences;
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use Data::Dumper;
use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use MediaWords::Solr;
use MediaWords::DBI::Timespans;
use MediaWords::Controller::Api::V2::Sentences;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { count => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = $topics_id;
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

    my $timespan = MediaWords::DBI::Timespans::require_timespan_for_topic(
        $c->dbis,
        $c->stash->{ topics_id },
        int( $c->req->params->{ timespans_id } // 0 ),
        int( $c->req->params->{ snapshots_id } // 0 )
    );

    my $q = $c->req->params->{ q };

    my $timespan_clause = "timespans_id:$timespan->{ timespans_id }";

    $q = $q ? "$timespan_clause AND ($q)" : $timespan_clause;

    $c->req->params->{ q } = $q;

    $c->req->params->{ split_start_date } ||= substr( $timespan->{ start_date }, 0, 12 );
    $c->req->params->{ split_end_date }   ||= substr( $timespan->{ end_date },   0, 12 );

    return $c->controller( 'Api::V2::Sentences' )->count_GET( $c );
}

1;
