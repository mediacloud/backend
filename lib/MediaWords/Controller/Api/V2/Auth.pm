package MediaWords::Controller::Api::V2::Auth;

# api controller for handling auth token generation

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base 'Catalyst::Controller';

use MediaWords::Controller::Api::V2::MC_Controller_REST;
use MediaWords::DBI::Auth;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(    #
    action => {         #
        single  => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },
        profile => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

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

    if ( $userauth->{ active } )
    {
        WARN "User with email '$email' is not active.";
        return 0;
    }

    return 0 unless ( MediaWords::DBI::Auth::password_hash_is_valid( $userauth->{ password_hash }, $password ) );

    return $userauth;
}

# get an ip token for the current user and ip request
sub _get_ip_token_for_user
{
    my ( $c, $user ) = @_;

    my $db = $c->dbis;

    my $ip_address = MediaWords::DBI::Auth::get_request_ip_address( $c );

    if ( !$ip_address )
    {
        WARN "Unable to find ip address for request";
        return 0;
    }

    my $auth_user_ip_token = $db->query( <<END, $user->{ auth_users_id }, $ip_address )->hash;
select * from auth_user_ip_tokens where auth_users_id = ? and ip_address = ?
END

    my $auit_hash = { auth_users_id => $user->{ auth_users_id }, ip_address => $ip_address };
    $auth_user_ip_token //= $db->create( 'auth_user_ip_tokens', $auit_hash );

    return $auth_user_ip_token->{ api_token };
}

# login and get an ip token for the logged in user.  return 0 on error or failed login.
sub _login_and_get_ip_token_for_user
{
    my ( $c, $email, $password ) = @_;

    my $user = _login( $c->dbis, $email, $password );

    return 0 unless ( $user );

    return _get_ip_token_for_user( $c, $user );
}

sub single_GET : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $email    = $c->req->params->{ username };
    my $password = $c->req->params->{ password };

    my $token = _login_and_get_ip_token_for_user( $c, $email, $password );

    if ( !$token )
    {
        $self->status_ok( $c, entity => [ { 'result' => 'not found' } ] );
        return;
    }

    $self->status_ok( $c, entity => [ { 'result' => 'found', 'token' => $token } ] );
}

# return info about currently logged in user
sub profile : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $user  = MediaWords::DBI::Auth::user_for_api_token_catalyst( $c );
    my $email = $user->{ email };

    my $userinfo;
    eval { $userinfo = MediaWords::DBI::Auth::user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "Unable to find user with email '$email'";
    }

    delete $userinfo->{ api_token };

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
