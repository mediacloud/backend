package MediaWords::Controller::Api::V2::Auth;

# api controller for handling API key generation

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base 'Catalyst::Controller';

use MediaWords::Controller::Api::V2::MC_Controller_REST;
use MediaWords::DBI::Auth;
use MediaWords::DBI::Auth::Roles;
use MediaWords::Util::URL;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(    #
    action => {         #
        register                 => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        activate                 => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        resend_activation_link   => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        send_password_reset_link => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        reset_password           => { Does => [ qw( ~AdminAuthenticated ~Throttled ~Logged ) ] },
        login                    => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        profile                  => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        change_password          => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        reset_api_key            => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

sub _user_profile_hash($$)
{
    my ( $db, $email ) = @_;

    my $user;
    eval { $user = MediaWords::DBI::Auth::Info::user_info( $db, $email ); };
    if ( $@ or ( !$user ) )
    {
        die "Unable to fetch user profile for user '$email'.";
    }

    return {
        'auth_users_id' => $user->user_id(),
        'email'         => $user->email(),
        'full_name'     => $user->full_name(),

        # Always return global (non-IP limited) API key because we don't know who is requesting
        # the profile (dashboard or the user itself)
        'api_key' => $user->global_api_key(),

        'notes'        => $user->notes(),
        'created_date' => $user->created_date(),
        'active'       => $user->active(),
        'auth_roles'   => $user->role_names(),
        'limits'       => {
            'weekly' => {
                'requests' => {
                    'used'  => $user->weekly_requests_sum(),
                    'limit' => $user->weekly_requests_limit(),
                },
                'requested_items' => {
                    'used'  => $user->weekly_requested_items_sum(),
                    'limit' => $user->weekly_requested_items_limit(),
                }
            }
        }
    };
}

sub register : Local
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
        my $role_ids = MediaWords::DBI::Auth::Roles::default_role_ids( $db );
        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                   => $email,
            full_name               => $full_name,
            notes                   => $notes,
            password                => $password,
            password_repeat         => $password,
            role_ids                => $role_ids,
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

sub activate : Local
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

sub resend_activation_link : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $data = $c->req->data;

    my $email = $data->{ email };
    unless ( $email )
    {
        die "'email' is not set.";
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

    my $subscribe_to_newsletter = 1;
    eval {
        MediaWords::DBI::Auth::Register::send_user_activation_token( $db, $email, $activation_url,
            $subscribe_to_newsletter );
    };
    if ( $@ )
    {
        die "Unable to resend activation link: $@";
    }

    $self->status_ok( $c, entity => { 'success' => 1 } );
}

sub send_password_reset_link : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $data = $c->req->data;

    my $email = $data->{ email };
    unless ( $email )
    {
        die "'email' is not set.";
    }

    my $password_reset_url = $data->{ password_reset_url };
    unless ( $password_reset_url )
    {
        die "'password_reset_url' is not set.";
    }

    unless ( MediaWords::Util::URL::is_http_url( $password_reset_url ) )
    {
        die "'password_reset_url' does not look like a HTTP URL.";
    }

    eval { MediaWords::DBI::Auth::ResetPassword::send_password_reset_token( $db, $email, $password_reset_url ); };
    if ( $@ )
    {
        die "Unable to send password reset link: $@";
    }

    $self->status_ok( $c, entity => { 'success' => 1 } );
}

sub reset_password : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $data = $c->req->data;

    my $email = $data->{ email };
    unless ( $email )
    {
        die "'email' is not set.";
    }

    my $password_reset_token = $data->{ password_reset_token };
    unless ( $password_reset_token )
    {
        die "'password_reset_token' is not set.";
    }

    my $new_password = $data->{ new_password };
    unless ( $new_password )
    {
        die "'new_password' is not set.";
    }

    eval {
        MediaWords::DBI::Auth::ChangePassword::change_password_with_reset_token( $db, $email, $password_reset_token,
            $new_password, $new_password );
    };
    if ( $@ )
    {
        die "Unable to reset password: $@";
    }

    $self->status_ok( $c, entity => { 'success' => 1 } );
}

sub login : Local
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

    my $ip_address = $c->request_ip_address();

    my $user;
    eval { $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password ); };
    if ( $@ or ( !$user ) )
    {
        die "Unable to log in: $@";
    }

    my $user_hash = _user_profile_hash( $db, $email );

    $self->status_ok( $c, entity => { 'success' => 1, 'profile' => $user_hash } );
}

# return info about currently logged in user
sub profile : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $email = $c->user->username;
    unless ( $email )
    {
        die "User is not logged in.";
    }

    my $user_hash = _user_profile_hash( $db, $email );

    return $self->status_ok( $c, entity => $user_hash );
}

sub change_password : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $email = $c->user->username;
    unless ( $email )
    {
        die "User is not logged in.";
    }

    my $data = $c->req->data;

    my $old_password = $data->{ old_password };
    unless ( $old_password )
    {
        die "'old_password' is not set.";
    }

    my $new_password = $data->{ new_password };
    unless ( $new_password )
    {
        die "'new_password' is not set.";
    }

    eval {
        MediaWords::DBI::Auth::ChangePassword::change_password_with_old_password( $db, $email, $old_password,
            $new_password, $new_password );
    };
    if ( $@ )
    {
        die "Unable to change password: $@";
    }

    $self->status_ok( $c, entity => { 'success' => 1 } );
}

sub reset_api_key : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $email = $c->user->username;
    unless ( $email )
    {
        die "User is not logged in.";
    }

    eval { MediaWords::DBI::Auth::Profile::regenerate_api_key( $db, $email ); };
    if ( $@ )
    {
        die "Unable to reset API key: $@";
    }

    my $user_hash = _user_profile_hash( $db, $email );

    $self->status_ok( $c, entity => { 'success' => 1, 'profile' => $user_hash } );
}

1;
