package Catalyst::Authentication::Store::MediaWords;

# local plugin to help with the authentication

use strict;
use warnings;
use Moose;
use namespace::autoclean;

with 'MooseX::Emulate::Class::Accessor::Fast';

use Modern::Perl '2012';
use MediaWords::CommonLibs;
use MediaWords::DB;
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

    my $dbis = $c->dbis;

    my $username = $userinfo->{ 'username' } || '';

    my $user = $dbis->query(
        <<"EOF",
        SELECT users_id, email, password
        FROM auth_users
        WHERE email = ?
        ORDER BY users_id
        LIMIT 1
EOF
        $username
    )->hash;

    if ( ref( $user ) eq 'HASH' and $user->{ users_id } )
    {
        say 'User found';
        return Catalyst::Authentication::User::Hash->new(
            'id'       => $user->{ users_id },
            'username' => $user->{ email },
            'password' => $user->{ password }
        );
    }
    else
    {
        say 'User not found';
        return 0;
    }

}

# does any restoration required when obtaining a user from the session
sub from_session
{
    my ( $self, $c, $user ) = @_;

    return $user if ref $user;
    return $self->find_user( { id => $user } );
}

# provides information about what the user object supports
sub user_supports
{
    my $self = shift;
    Catalyst::Authentication::User::Hash->supports( @_ );
}

__PACKAGE__;
