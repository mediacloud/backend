package Catalyst::Authentication::Credential::MediaWords::APIKey;

#
# Authenticate users with API key.
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

# API key parameter
Readonly our $API_KEY_FIELD => 'key';

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

    my $api_key    = $authinfo->{ $API_KEY_FIELD };
    my $ip_address = $c->request_ip_address();

    if ( $api_key and $ip_address )
    {

        my $user;
        eval { $user = MediaWords::DBI::Auth::Login::login_with_api_key( $db, $api_key, $ip_address ); };
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
