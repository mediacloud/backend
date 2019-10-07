package MediaWords::Controller::Api::V2::Topics::Foci;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = $topics_id;
}

sub foci : Chained('apibase') : PathPart('foci') : CaptureArgs(0)
{
}

sub list : Chained('foci') : Args(0) : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id = $c->stash->{ topics_id };
    my $focal_sets_id = int( $c->req->params->{ focal_sets_id } // 0 )
      || die( 'missing required param focal_sets_id' );

    my $foci = $db->query( <<SQL, $focal_sets_id )->hashes;
select foci_id, name, description, arguments->>'query' query
    from foci
    where focal_sets_id = \$1
    order by name desc
SQL

    $self->status_ok( $c, entity => { foci => $foci } );
}

1;
