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

    my $api_key;
    eval {
        $api_key = MediaWords::DBI::Auth::Login::login_with_email_password_get_ip_api_key(
            $db,                        #
            $email,                     #
            $password,                  #
            $c->request_ip_address()    #
        );
    };
    if ( $@ or ( !$api_key ) )
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

    my $api_key;
    eval {
        $api_key = MediaWords::DBI::Auth::Login::login_with_email_password_get_ip_api_key(
            $db,                        #
            $email,                     #
            $password,                  #
            $c->request_ip_address()    #
        );
    };
    if ( $@ or ( !$api_key ) )
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

    my $userinfo;
    eval { $userinfo = MediaWords::DBI::Auth::Login::login_with_api_key_catalyst( $c ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "Unable to find user for given API key.";
    }

    my $user_hash = {
        auth_users_id                => $userinfo->id(),
        email                        => $userinfo->email(),
        full_name                    => $userinfo->full_name(),
        notes                        => $userinfo->notes(),
        active                       => $userinfo->active(),
        weekly_requests_sum          => $userinfo->weekly_requests_sum(),
        weekly_requested_items_sum   => $userinfo->weekly_requested_items_sum(),
        weekly_requests_limit        => $userinfo->weekly_requests_limit(),
        weekly_requested_items_limit => $userinfo->weekly_requested_items_limit(),
        roles                        => [ map { $_->role() } @{ $userinfo->roles() } ],
    };

    return $self->status_ok( $c, entity => $user_hash );
}

1;
