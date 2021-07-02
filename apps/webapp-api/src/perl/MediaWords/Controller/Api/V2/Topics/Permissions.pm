package MediaWords::Controller::Api::V2::Topics::Permissions;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use HTTP::Status qw(:constants);
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use MediaWords::DBI::Auth::Info;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    action => {
        user_list => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list      => { Does => [ qw( ~TopicsAdminAuthenticated ~Throttled ~Logged ) ] },
        update    => { Does => [ qw( ~TopicsAdminAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub user_list : Chained( '/') : PathPart( 'api/v2/topics/permissions/user/list' ) : Args(0) : ActionClass( 'MC_REST')
{

}

sub user_list_GET
{
    my ( $self, $c ) = @_;

    my $permissions = $c->dbis->query( <<SQL,
        SELECT
            u.email,
            tp.topics_id,
            tp.permission
        FROM topic_permissions AS tp
            INNER JOIN auth_users AS u USING (auth_users_id)
        WHERE u.auth_users_id = ?
SQL
        $c->stash->{ api_auth }->user_id()
    )->hashes;

    $self->status_ok( $c, entity => { permissions => $permissions } );
}

sub apibase : Chained('/') : PathPart('api/v2/topics/') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = $topics_id;
}

sub permissions : Chained('apibase') : PathPart('permissions') : CaptureArgs(0)
{

}

sub list : Chained('permissions') : Args(0) : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $permissions = $c->dbis->query( <<SQL,
        SELECT
            u.email,
            tp.topics_id,
            tp.permission
        FROM topic_permissions AS tp
            JOIN auth_users AS u USING (auth_users_id)
        WHERE tp.topics_id = ?
SQL
        $c->stash->{ topics_id }
    )->hashes;

    $self->status_ok( $c, entity => { permissions => $permissions } );
}

sub update : Chained('permissions') : Args(0) : ActionClass('MC_REST')
{

}

sub update_PUT
{
    my ( $self, $c ) = @_;

    my $topics_id = $c->stash->{ topics_id };
    my $data      = $c->req->data;

    $self->require_fields( $c, [ qw/email permission/ ] );

    my $permission = lc( $data->{ permission } );
    my $email      = lc( $data->{ email } );

    my $db = $c->dbis;

    if ( !grep { $_ eq $permission } qw(write read admin none) )
    {
        $c->response->status( HTTP_BAD_REQUEST );
        die( "Unknown permission '$permission'" );
    }

    my $auth_user;
    eval { $auth_user = MediaWords::DBI::Auth::Info::user_info( $db, $email ); };
    if ( $@ or ( !$auth_user ) )
    {
        $c->response->status( HTTP_BAD_REQUEST );
        die( "Unknown email '$email'" );
    }

    $db->query( <<SQL,
        DELETE FROM topic_permissions
        WHERE
            topics_id = ? AND
            auth_users_id = ?
SQL
        $topics_id, $auth_user->user_id()
    );

    my $permissions = [];
    if ( grep { $permission eq $_ } qw(read write admin) )
    {
        my $tp = { permission => $permission, auth_users_id => $auth_user->user_id(), topics_id => $topics_id };
        $db->create( 'topic_permissions', $tp );
        $permissions = [ $tp ];
    }

    $self->status_ok( $c, entity => { permissions => $permissions } );
}

1;
