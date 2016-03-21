package Catalyst::Authentication::Store::MediaWords;

# local plugin to help with the authentication

use strict;
use warnings;
use Moose;
use namespace::autoclean;

with 'MooseX::Emulate::Class::Accessor::Fast';

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::DBI::Auth;
use Catalyst::Authentication::User::Hash;
use Scalar::Util qw( blessed );

__PACKAGE__->mk_accessors( qw( _config ) );

# instantiates the store object
sub new
{
    my ( $class, $config, $app, $realm ) = @_;

    my $self = bless { _config => $config }, $class;
    return $self;
}

# locates a user using data contained in the hashref
sub find_user
{
    my ( $self, $userinfo, $c ) = @_;

    my $username = $userinfo->{ 'username' } || '';

    # Check if user has tried to log in unsuccessfully before and now is trying
    # again too fast
    if ( MediaWords::DBI::Auth::user_is_trying_to_login_too_soon( $c->dbis, $username ) )
    {
        print STDERR "User '$username' is trying to log in too soon after the last unsuccessful attempt.\n";
        return 0;
    }

    # Check if user exists and is active; if so, fetch user info,
    # password hash and a list of roles
    my $user = MediaWords::DBI::Auth::user_auth( $c->dbis, $username );
    if ( $user and $user->{ active } )
    {
        return Catalyst::Authentication::User::Hash->new(
            'id'       => $user->{ auth_users_id },
            'username' => $user->{ email },
            'password' => $user->{ password_hash },

            # List of roles get hashed into the user object and are refetched from the
            # database each and every time the user tries to access a page (via the
            # from_session() subroutine). This is done because a list of roles might
            # change while the user is still logged in.
            'roles' => $user->{ roles }
        );
    }
    else
    {
        say STDERR "User '$username' not found or inactive";
        return 0;
    }

}

# does any restoration required when obtaining a user from the session
sub from_session
{
    my ( $self, $c, $user ) = @_;

    if ( ref $user )
    {

        # Check the database for the user each and every time a page is opened because
        # the user might have been removed from the user list
        return $self->find_user( $user, $c );
    }
    else
    {
        return $self->find_user( { username => $user }, $c );
    }

    return $user;
}

# provides information about what the user object supports
sub user_supports
{
    my $self = shift;
    Catalyst::Authentication::User::Hash->supports( @_ );
}

__PACKAGE__;
