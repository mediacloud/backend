package MediaWords::Controller::Api::V2::Auth;

# api controller for handling API key generation

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base 'Catalyst::Controller';

use MediaWords::Controller::Api::V2::MC_Controller_REST;
use MediaWords::DBI::Auth;
use MediaWords::Util::URL;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(    #
    action => {         #
        register => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        activate => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        single   => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        login    => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        profile  => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub _user_profile_hash($$)
{
    my ( $db, $email ) = @_;

    my $user;
    eval { $user = MediaWords::DBI::Auth::Profile::user_info( $db, $email ); };
    if ( $@ or ( !$user ) )
    {
        die "Unable to fetch user profile for user '$email'.";
    }

    return {
        auth_users_id                => $user->id(),
        email                        => $user->email(),
        full_name                    => $user->full_name(),
        notes                        => $user->notes(),
        active                       => $user->active(),
        weekly_requests_sum          => $user->weekly_requests_sum(),
        weekly_requested_items_sum   => $user->weekly_requested_items_sum(),
        weekly_requests_limit        => $user->weekly_requests_limit(),
        weekly_requested_items_limit => $user->weekly_requested_items_limit(),
        roles                        => $user->role_names(),
    };
}

sub register : Local : ActionClass('MC_REST')
{
}

sub register_GET : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $data = $c->req->data;

    my $email = $data->{ email };
    unless ( $email )
    {
        die "'email' is not set.";
    }

    my $password = $data->{ password };
    unless ( $password )
    {
        die "'password' is not set.";
    }

    my $full_name = $data->{ full_name };
    unless ( $full_name )
    {
        die "'full_name' is not set.";
    }

    my $notes = $data->{ notes };
    unless ( defined $notes )
    {
        die "'notes' is undefined (should be at least an empty string).";
    }

    my $subscribe_to_newsletter = $data->{ subscribe_to_newsletter };
    unless ( defined $subscribe_to_newsletter )
    {
        die "'subscribe_to_newsletter' is undefined (should be at least an empty string).";
    }

    my $activation_url = $data->{ activation_url };
    unless ( $activation_url )
    {
        die "'activation_url' is not set.";
    }

    unless ( MediaWords::Util::URL::is_http_url( $activation_url ) )
    {
        die "'activation_url' does not look like a HTTP URL.";
    }

    eval {
        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                   => $email,
            full_name               => $full_name,
            notes                   => $notes,
            password                => $password,
            password_repeat         => $password,
            role_ids                => MediaWords::DBI::Auth::Roles::default_role_ids( $db ),
            subscribe_to_newsletter => $subscribe_to_newsletter,

            # User has to activate own account via email
            active         => 0,
            activation_url => $activation_url,
        );
        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    if ( $@ )
    {
        die "Unable to add user: $@";
    }

    $self->status_ok( $c, entity => { 'success' => 1 } );
}

sub activate : Local : ActionClass('MC_REST')
{
}

sub activate_GET : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $data = $c->req->data;

    my $email = $data->{ email };
    unless ( $email )
    {
        die "'email' is not set.";
    }

    my $activation_token = $data->{ activation_token };
    unless ( $activation_token )
    {
        die "'activation_token' is not set.";
    }

    eval { MediaWords::DBI::Auth::Register::activate_user_via_token( $db, $email, $activation_token ); };
    if ( $@ )
    {
        die "Unable to activate user: $@";
    }

    my $user_hash = _user_profile_hash( $db, $email );

    $self->status_ok( $c, entity => { 'success' => 1, 'profile' => $user_hash } );
}

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

    $self->status_ok( $c, entity => { 'success' => 1, 'api_key' => $api_key } );
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

    my $email = $c->user->username;
    my $user_hash = _user_profile_hash( $db, $email );

    return $self->status_ok( $c, entity => $user_hash );
}

1;
