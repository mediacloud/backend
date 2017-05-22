package Catalyst::Authentication::Credential::MediaWords;

#
# Media Cloud Catalyst credentials package, uses ::DBI::Auth to do the authentication.
#
# Adapted from Catalyst::Authentication::Credential::Password.
#

use strict;
use warnings;

use Moose;
use namespace::autoclean;

with 'MooseX::Emulate::Class::Accessor::Fast';

use Catalyst::Exception ();
use Readonly;

__PACKAGE__->mk_accessors( qw/realm/ );

use MediaWords::DBI::Auth::Password;

Readonly my $password_field => 'password';

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

    ## because passwords may be in a hashed format, we have to make sure that we remove the
    ## password_field before we pass it to the user routine, as some auth modules use
    ## all data passed to them to find a matching user...
    my $userfindauthinfo = { %{ $authinfo } };
    delete( $userfindauthinfo->{ $password_field } );

    my $user_obj = $realm->find_user( $userfindauthinfo, $c );
    if ( ref( $user_obj ) )
    {
        my $password       = $authinfo->{ $password_field };
        my $storedpassword = $user_obj->get( $password_field );

        if ( MediaWords::DBI::Auth::Password::password_hash_is_valid( $storedpassword, $password ) )
        {
            return $user_obj;
        }
    }
    else
    {
        if ( $c->debug )
        {
            $c->log->debug( 'Unable to locate user matching user info provided in realm: ' . $realm->name );
        }
        return;
    }
}

__PACKAGE__;
