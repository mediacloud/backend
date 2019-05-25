package MediaWords;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Catalyst::Runtime '5.80';
use v5.22;

use MediaWords::Util::Paths;

use Net::IP;
use Readonly;
use URI;

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a YAML file in the
#                 application's home directory
# Plugin::Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
  ConfigLoader
  Static::Simple
  StackTrace
  Authentication
  Authorization::Roles
  Authorization::ACL
  /;

our $VERSION = '0.01';

# Configure the application.
#
# Note that settings in mediawords.yml (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with a external configuration file acting as an override for
# local deployment.

my $config = __PACKAGE__->config( -name => 'MediaWords' );

# Authentication realms
Readonly our $AUTH_REALM_USERNAME_PASSWORD => 'mc_auth_realm_username_password';
Readonly our $AUTH_REALM_API_KEY           => 'mc_auth_realm_api_key';

# Set Catalyst home for path_to() to work and resolve .yml templates correctly
__PACKAGE__->config( home => '/var/www/' );

# Configure authentication scheme
__PACKAGE__->config(
    'Plugin::Authentication' => {
        'default_realm'               => $AUTH_REALM_USERNAME_PASSWORD,
        $AUTH_REALM_USERNAME_PASSWORD => {
            'credential' => { 'class' => 'MediaWords::UsernamePassword' },
            'store'      => { 'class' => 'MediaWords' }
        },
        $AUTH_REALM_API_KEY => {
            'credential' => { 'class' => 'MediaWords::APIKey' },
            'store'      => { 'class' => 'MediaWords' }
        },
    }
);

# Exit an action chain when there is an error raised in any action (thus
# terminating the chain early)
__PACKAGE__->config( abort_chain_on_error_fix => 1 );

# Start the application
__PACKAGE__->setup;

# Get the ip address of the given catalyst request, using the x-forwarded-for header
# if present and ip address is localhost
sub request_ip_address($)
{
    my ( $self ) = @_;

    my $headers     = $self->req->headers;
    my $req_address = $self->req->address;

    my $forwarded_ip = $headers->header( 'X-Real-IP' ) || $headers->header( 'X-Forwarded-For' );

    if ( $forwarded_ip )
    {
        my $net_ip = new Net::IP( $req_address ) or die( Net::IP::Error() );
        my $iptype = uc( $net_ip->iptype() );

        # 127.0.0.1 / ::1, 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16?
        if ( $iptype eq 'PRIVATE' or $iptype eq 'LOOPBACK' )
        {
            return $forwarded_ip;
        }
    }

    return $req_address;
}

# shortcut to dbis model
sub dbis
{

    return $_[ 0 ]->model( 'DBIS' )->dbis( $_[ 0 ]->req );
}

1;
