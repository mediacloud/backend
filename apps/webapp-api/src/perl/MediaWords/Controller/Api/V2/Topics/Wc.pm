package MediaWords::Controller::Api::V2::Topics::Wc;
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

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;

    $topics_id = int( $topics_id // 0 );
    unless ( $topics_id )
    {
        die "topics_id is unset.";
    }

    $c->stash->{ topics_id } = $topics_id;
}

sub wc : Chained('apibase') : PathPart('wc') : CaptureArgs(0)
{

}

sub list : Chained('wc') : Args(0) : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db       = $c->dbis;
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

    return $c->controller( 'Api::V2::Wc' )->list_GET( $c );
}

1;
