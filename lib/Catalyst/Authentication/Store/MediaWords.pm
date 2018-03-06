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

# Confirm that the logged in still exists
sub find_user
{
    my ( $self, $userinfo, $c ) = @_;

    my $db = $c->dbis;
    my $email = $userinfo->{ username } || '';

    # Check if user exists and is active
    my $userauth;
    eval { $userauth = MediaWords::DBI::Auth::Info::user_info( $db, $email ); };
    if ( $@ or ( !$userauth ) )
    {
        WARN "User '$email' was not found.";
        return 0;
    }

    return Catalyst::Authentication::User::Hash->new(
        'id'       => $userauth->id(),
        'username' => $userauth->email(),

        # List of roles get hashed into the user object and are refetched from the
        # database each and every time the user tries to access a page (via the
        # from_session() subroutine). This is done because a list of roles might
        # change while the user is still logged in.
        'roles' => $userauth->role_names(),
    );
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
