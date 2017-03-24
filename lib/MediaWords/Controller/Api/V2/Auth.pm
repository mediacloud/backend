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

# try to login with the given email and password.  return the email if login is successful.
sub _login
{
    my ( $db, $email, $password ) = @_;

    return 0 unless ( $email && $password );

    my $userauth;
    eval { $userauth = MediaWords::DBI::Auth::user_auth( $db, $email ); };
    if ( $@ or ( !$userauth ) )
    {
        WARN "Unable to find authentication roles for email '$email'";
        return 0;
    }

    unless ( $userauth->{ active } )
    {
        WARN "User with email '$email' is not active.";
        return 0;
    }

    return 0 unless ( MediaWords::DBI::Auth::Password::password_hash_is_valid( $userauth->{ password_hash }, $password ) );

    return $userauth;
}

# login and get an IP API key for the logged in user.  return 0 on error or failed login.
sub _login_and_get_ip_api_key_for_user
{
    my ( $c, $email, $password ) = @_;

    my $db = $c->dbis;

    my $user = _login( $db, $email, $password );

    return 0 unless ( $user );

    my $ip_address = $c->request_ip_address();

    unless ( $ip_address )
    {
        WARN "Unable to find IP address for request";
        return 0;
    }

    my $auth_user_ip_api_key = $db->query(
        <<SQL,
        SELECT *
        FROM auth_user_ip_address_api_keys
        WHERE auth_users_id = ?
          AND ip_address = ?
SQL
        $user->{ auth_users_id }, $ip_address
    )->hash;

    my $auit_hash = { auth_users_id => $user->{ auth_users_id }, ip_address => $ip_address };
    $auth_user_ip_api_key //= $db->create( 'auth_user_ip_address_api_keys', $auit_hash );

    return $auth_user_ip_api_key->{ api_key };
}

sub login_GET : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $email    = $c->req->params->{ username };
    my $password = $c->req->params->{ password };

    my $api_key = _login_and_get_ip_api_key_for_user( $c, $email, $password );

    unless ( $api_key )
    {
        die "User '$email' was not found or password is incorrect.";
    }

    $self->status_ok(
        $c,
        entity => {
            'result'  => 'found',     #
            'token'   => $api_key,    # legacy; renamed to API key
            'api_key' => $api_key,    #
        }
    );
}

sub single_GET : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    return $self->login_GET( $c, @_ );
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
