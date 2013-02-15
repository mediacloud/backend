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

    my $username = $userinfo->{ 'username' } || '';

    # Check if user exists and is active; if so, fetch user info,
    # password hash and a list of roles
    my $user = $c->dbis->query(
        <<"EOF",
        SELECT auth_users.users_id,
               auth_users.email,
               auth_users.password_hash,
               ARRAY_TO_STRING(ARRAY_AGG(role), ' ') AS roles
        FROM auth_users
            LEFT JOIN auth_users_roles_map
                ON auth_users.users_id = auth_users_roles_map.users_id
            LEFT JOIN auth_roles
                ON auth_users_roles_map.roles_id = auth_roles.roles_id
        WHERE auth_users.email = ?
              AND auth_users.active = true
        GROUP BY auth_users.users_id,
                 auth_users.email,
                 auth_users.password_hash
        ORDER BY auth_users.users_id
        LIMIT 1
EOF
        $username
    )->hash;

    if ( ref( $user ) eq 'HASH' and $user->{ users_id } )
    {
        return Catalyst::Authentication::User::Hash->new(
            'id'       => $user->{ users_id },
            'username' => $user->{ email },
            'password' => $user->{ password_hash },

            # List of roles get hashed into the user object; if the role list changes
            # (e.g. admin adds or removes some roles), the user's session (if any) is thrown out.
            # Possible improvement would be implementing a custom Catalyst::Authentication::User::MediaWords
            # and checking a roles each and every time a resource is accessed.
            'roles' => [ split( ' ', $user->{ roles } ) ]
        );
    }
    else
    {
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
