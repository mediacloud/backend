package MediaWords::Controller::Api::V2::Auth;

# api controller for handling auth token generation

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use base 'Catalyst::Controller';

use MediaWords::Controller::Api::V2::MC_Controller_REST;
use MediaWords::DBI::Auth;
use MediaWords::DBI::StorySubsets;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

sub single : Local : ActionClass('REST') : Does('~ApiKeyAuthenticated') : Does('~Throttled') : Does('~Logged')
{
}

# try to login with the given username and password.  return the username if login is successful.
sub _login
{
    my ( $db, $username, $password ) = @_;

    return 0 unless ( $username && $password );

    my $user = MediaWords::DBI::Auth::user_auth( $db, $username );

    return 0 unless ( $user && $user->{ active } );

    return 0 unless ( MediaWords::DBI::Auth::password_hash_is_valid( $user->{ password_hash }, $password ) );

    return 0 unless ( grep { $_ =~ /^admin|admin-readonly|stories-api|public-api$/ } @{ $user->{ roles } } );

    return $user;

}

# get an ip token for the current user and ip request
sub _get_ip_token_for_user
{
    my ( $c, $user ) = @_;

    my $db = $c->dbis;

    my $ip_address = MediaWords::DBI::Auth::get_request_ip_address( $c );

    if ( !$ip_address )
    {
        warn( "Unable to find ip address for request" );
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
    my ( $c, $username, $password ) = @_;

    my $user = _login( $c->dbis, $username, $password );

    return 0 unless ( $user );

    return _get_ip_token_for_user( $c, $user );
}

sub single_GET : Local : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $username = $c->req->params->{ username };
    my $password = $c->req->params->{ password };

    my $token = _login_and_get_ip_token_for_user( $c, $username, $password );

    if ( !$token )
    {
        $self->status_ok( $c, entity => [ { 'result' => 'not found' } ] );
        return;
    }

    $self->status_ok( $c, entity => [ { 'result' => 'found', 'token' => $token } ] );
}

1;
