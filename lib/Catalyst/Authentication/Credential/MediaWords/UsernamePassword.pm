package Catalyst::Authentication::Credential::MediaWords::UsernamePassword;

#
# Authenticate users with username and password.
#

use strict;
use warnings;

use Moose;
use namespace::autoclean;

with 'MooseX::Emulate::Class::Accessor::Fast';

use Catalyst::Exception ();
use Readonly;

__PACKAGE__->mk_accessors( qw/realm/ );

use MediaWords::DBI::Auth::Login;

Readonly my $USERNAME_FIELD => 'username';
Readonly my $PASSWORD_FIELD => 'password';

sub new
{
    my ( $class, $config, $app, $realm ) = @_;

    my $self = {};
    bless $self, $class;

    $self->realm( $realm );

    return $self;
}

sub authenticate
{
    my ( $self, $c, $realm, $authinfo ) = @_;

    my $db = $c->dbis;

    my $username = $authinfo->{ $USERNAME_FIELD };
    my $password = $authinfo->{ $PASSWORD_FIELD };

    if ( $username and $password )
    {

        my $user;
        eval { $user = MediaWords::DBI::Auth::Login::login_with_email_password( $c->dbis, $username, $password ); };
        unless ( $@ or ( !$user ) )
        {
            my $user_obj = $realm->find_user( { username => $user->email() }, $c );
            if ( ref( $user_obj ) )
            {
                return $user_obj;
            }
        }
    }

    if ( $c->debug )
    {
        $c->log->debug( 'Unable to locate user matching user info provided in realm: ' . $realm->name );
    }

    return undef;
}

__PACKAGE__;
