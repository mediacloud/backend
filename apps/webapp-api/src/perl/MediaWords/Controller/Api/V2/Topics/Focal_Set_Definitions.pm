package MediaWords::Controller::Api::V2::Topics::Focal_Set_Definitions;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        list   => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] },
        create => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
        update => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
        delete => { Does => [ qw( ~TopicsWriteAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $v ) = @_;
    $c->stash->{ topics_id } = $v;
}

sub focal_set_definitions : Chained('apibase') : PathPart('focal_set_definitions') : CaptureArgs( 1 )
{
    my ( $self, $c, $v ) = @_;

    $c->stash->{ focal_set_definitions_id } = $v;
}

sub list : Chained('apibase') : PathPart( 'focal_set_definitions/list' ) : Args(0) : ActionClass('MC_REST')
{
}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id = $c->stash->{ topics_id };

    my $fsds = $db->query( <<SQL,
        SELECT
            focal_set_definitions_id,
            name,
            description,
            focal_technique,
            false AS is_exclusive
        FROM focal_set_definitions
        WHERE topics_id = \$1
        ORDER BY name
SQL
        $topics_id
    )->hashes;

    $fsds = $db->attach_child_query( $fsds, <<SQL,
        SELECT
            focal_set_definitions_id,
            focus_definitions_id,
            name,
            description,
            arguments->>'query' AS query
        FROM focus_definitions
SQL
        'focus_definitions', 'focal_set_definitions_id'
    );

    $self->status_ok( $c, entity => { focal_set_definitions => $fsds } );
}

sub create : Chained('apibase') : PathPart( 'focal_set_definitions/create' ) : Args(0) : ActionClass('MC_REST')
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id = $c->stash->{ topics_id };
    my $data      = $c->req->data;

    $self->require_fields( $c, [ qw/name description focal_technique/ ] );

    my $fsd = {
        name            => $data->{ name },
        description     => $data->{ description },
        focal_technique => $data->{ focal_technique },
        topics_id       => $topics_id
    };

    $fsd = $db->create( 'focal_set_definitions', $fsd );

    $self->status_ok( $c, entity => { focal_set_definitions => [ $fsd ] } );
}

sub delete : Chained('focal_set_definitions') : Args(0) : ActionClass('MC_REST')
{
}

sub delete_PUT
{
    my ( $self, $c ) = @_;

    my $topics_id                = $c->stash->{ topics_id };
    my $focal_set_definitions_id = $c->stash->{ focal_set_definitions_id };

    $c->dbis->query( <<SQL,
        DELETE FROM focal_set_definitions
        WHERE
            topics_id = \$1 AND
            focal_set_definitions_id = \$2
SQL
        $topics_id, $focal_set_definitions_id
    );

    $self->status_ok( $c, entity => { success => 1 } );
}

sub update : Chained('focal_set_definitions') : Args(0) : ActionClass('MC_REST')
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id                = $c->stash->{ topics_id };
    my $focal_set_definitions_id = $c->stash->{ focal_set_definitions_id };

    my $fsd = $self->update_table( $c, 'focal_set_definitions', $focal_set_definitions_id, [ qw/name description/ ] );

    $self->status_ok( $c, entity => { focal_set_definitions => [ $fsd ] } );
}

1;
