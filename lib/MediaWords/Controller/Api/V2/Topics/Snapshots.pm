package MediaWords::Controller::Api::V2::Topics::Snapshots;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = $topics_id;
}

sub snapshots : Chained('apibase') : PathPart('snapshots') : CaptureArgs(0)
{

}

sub list : Chained('snapshots') : Args(0) : ActionClass('MC_REST')
{

}

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $snapshots = $db->query( <<SQL )->hashes;
select snapshots_id, snapshot_date, note, state from snapshots order by snapshots_id desc
SQL

    $self->status_ok( $c, entity => { snapshots => $snapshots } );
}

1;
