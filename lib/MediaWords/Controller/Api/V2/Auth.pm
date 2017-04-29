package MediaWords::Controller::Api::V2::Auth;

# api controller for handling API key generation

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base 'Catalyst::Controller';

use MediaWords::Controller::Api::V2::MC_Controller_REST;
use MediaWords::DBI::Auth;
use MediaWords::DBI::Auth::Password;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(    #
    action => {         #
        single  => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        login   => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        profile => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub login : Local : ActionClass('MC_REST')
{
}

sub single : Local : ActionClass('MC_REST')
{
}

sub login_GET : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $data     = $c->req->data;
    my $email    = $data->{ username };
    my $password = $data->{ password };

    my $api_key =
      MediaWords::DBI::Auth::login_and_get_ip_api_key_for_user( $db, $email, $password, $c->request_ip_address() );
    unless ( $api_key )
    {
        die "User '$email' was not found or password is incorrect.";
    }

    $self->status_ok( $c, entity => { 'api_key' => $api_key } );
}

sub single_GET : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $email    = $c->req->params->{ username };
    my $password = $c->req->params->{ password };

    my $api_key =
      MediaWords::DBI::Auth::login_and_get_ip_api_key_for_user( $db, $email, $password, $c->request_ip_address() );
    unless ( $api_key )
    {
        $self->status_ok( $c, entity => [ { 'result' => 'not found' } ] );
        return;
    }

    $self->status_ok( $c, entity => [ { 'result' => 'found', 'token' => $api_key } ] );
}

# return info about currently logged in user
sub profile : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $user  = MediaWords::DBI::Auth::user_for_api_key_catalyst( $c );
    my $email = $user->{ email };

    my $userinfo;
    eval { $userinfo = MediaWords::DBI::Auth::user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "Unable to find user with email '$email'";
    }

    delete $userinfo->{ api_key };

    $userinfo->{ auth_roles } = $db->query( <<SQL, $email )->flat;
select ar.role
    from auth_roles ar
        join auth_users_roles_map aurm using ( auth_roles_id )
        join auth_users au using ( auth_users_id )
    where
        au.email = \$1
    order by auth_roles_id
SQL

    return $self->status_ok( $c, entity => $userinfo );
}

1;
