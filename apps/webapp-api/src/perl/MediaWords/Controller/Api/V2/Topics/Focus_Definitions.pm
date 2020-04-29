package MediaWords::Controller::Api::V2::Topics::Focus_Definitions;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Moose;
use Readonly;
use namespace::autoclean;

use MediaWords::Solr;
use MediaWords::Util::ParseJSON;

Readonly my $SQL_FIELD_LIST => "focus_definitions_id, name, description, arguments->>'query' query";

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

sub focus_definitions : Chained('apibase') : PathPart('focus_definitions') : CaptureArgs( 1 )
{
    my ( $self, $c, $v ) = @_;

    $c->stash->{ path_id } = $v;
}

sub list : Chained('apibase') : PathPart( 'focus_definitions/list' ) : Args(0) : ActionClass('MC_REST')
{
}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id = $c->stash->{ topics_id };

    my $focal_set_definitions_id = int( $c->req->params->{ focal_set_definitions_id } // 0 )
      || die( "missing required param focal_set_definitions_id" );

    my $fds = $db->query( <<SQL, $focal_set_definitions_id )->hashes;
select $SQL_FIELD_LIST
    from focus_definitions fd
    where
        focal_set_definitions_id = \$1
    order by name
SQL

    $self->status_ok( $c, entity => { focus_definitions => $fds } );
}

sub create : Chained('apibase') : PathPart( 'focus_definitions/create' ) : Args(0) : ActionClass('MC_REST')
{
}

sub create_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id = $c->stash->{ topics_id };
    my $data      = $c->req->data;

    $self->require_fields( $c, [ qw/name description query focal_set_definitions_id/ ] );

    eval { MediaWords::Solr::query_solr( $db, { q => $data->{ query }, rows => 0 } ) };
    die( "invalid solr query: $@" ) if ( $@ );

    my $fd = $db->query(
        <<SQL, $data->{ name }, $data->{ description }, $data->{ query }, $data->{ focal_set_definitions_id } )->hash;
insert into focus_definitions ( name, description, arguments, focal_set_definitions_id )
    select \$1, \$2, ( '{ "query": ' || to_json( \$3::text ) || ' }' )::json, \$4
    returning $SQL_FIELD_LIST
SQL

    $self->status_ok( $c, entity => { focus_definitions => [ $fd ] } );
}

sub delete : Chained('focus_definitions') : Args(0) : ActionClass('MC_REST')
{
}

sub delete_PUT
{
    my ( $self, $c ) = @_;

    my $topics_id            = $c->stash->{ topics_id };
    my $focus_definitions_id = $c->stash->{ path_id };

    $c->dbis->query( <<SQL, $focus_definitions_id );
delete from focus_definitions where focus_definitions_id = \$1
SQL

    $self->status_ok( $c, entity => { success => 1 } );
}

sub update : Chained('focus_definitions') : Args(0) : ActionClass('MC_REST')
{
}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id            = $c->stash->{ topics_id };
    my $focus_definitions_id = $c->stash->{ path_id };

    my $arguments;
    if ( my $query = $c->req->data->{ query } )
    {
        eval { MediaWords::Solr::query_solr( $db, { q => $query, rows => 0 } ) };
        die( "invalid solr query: $@" ) if ( $@ );

        $c->req->data->{ arguments } = MediaWords::Util::ParseJSON::encode_json( { query => $query } );
    }

    my $fd = $self->update_table( $c, 'focus_definitions', $focus_definitions_id, [ qw/name description arguments/ ] );

    $self->status_ok( $c, entity => { focus_definitions => [ $fd ] } );
}

1;
