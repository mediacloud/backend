package MediaWords;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;

use Catalyst::Runtime '5.80';
use v5.8;

#use Catalyst::Runtime;

use DBIx::Simple::MediaWords;
use MediaWords::Util::Config;
use URI;
use Bundle::MediaWords;

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a YAML file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
  ConfigLoader
  ConfigDefaults
  Static::Simple
  Unicode
  StackTrace
  I18N
  Authentication
  Authorization::Roles
  Authorization::ACL
  Session
  Session::Store::FastMmap
  Session::State::Cookie
  /;

our $VERSION = '0.01';

use HTML::FormFu;
use HTML::FormFu::Unicode;

# Configure the application.
#
# Note that settings in mediawords.yml (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with a external configuration file acting as an override for
# local deployment.

my $config = __PACKAGE__->config( -name => 'MediaWords' );

# Configure authentication scheme
__PACKAGE__->config(
    'Plugin::Authentication' => {
        default_realm => 'users',
        users         => {
            credential => {
                class              => 'Password',
                password_field     => 'password',
                password_type      => 'salted_hash',
                password_hash_type => 'SHA-256',
                password_salt_len  => 64
            },
            store => { class => 'MediaWords' }
        }
    }
);

# Start the application
__PACKAGE__->setup;

# Access rules
# https://metacpan.org/module/Catalyst::Plugin::Authorization::ACL
__PACKAGE__->deny_access_unless_any( "/admin", [ qw/admin/ ] );
__PACKAGE__->allow_access( "/dashboard" );
__PACKAGE__->allow_access( "/login" );
__PACKAGE__->allow_access( "/logout" );

sub uri_for
{
    my ( $self, $path, $args ) = @_;

    if ( !$self->config->{ mediawords }->{ base_url } )
    {
        shift( @_ );
        return $self->SUPER::uri_for( @_ );
    }

    my $uri = URI->new( $self->config->{ mediawords }->{ base_url } . $path );

    if ( $args )
    {
        $uri->query_form( $args );
    }

    return $uri->as_string();
}

sub create_form
{
    my ( $self, $args ) = @_;

    my $ret = HTML::FormFu::Unicode->new( $args );

    return $ret;
}

# Redirect unauthenticated users to login page
sub acl_access_denied
{
    my ( $c, $class, $action, $err ) = @_;

    if ( $c->user_exists )
    {
        $c->log->debug( 'User has been found, is not allowed to access page /' . $action );

        # Show the "unauthorized" message
        $c->res->body( 'You are not allowed to access page /' . $action );
        $c->res->status( 403 );
    }
    else
    {
        $c->log->debug( 'User not found, forwarding to /login' );

        # Redirect the user to the login page
        $c->response->redirect( $c->uri_for( '/login' ) );
    }

    # Continue denying access
    return 0;
}

# shortcut to dbis model
sub dbis
{

    return $_[ 0 ]->model( 'DBIS' )->dbis;
}

=head1 NAME

MediaWords - Catalyst based application

=head1 SYNOPSIS

    script/mediawords_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<MediaWords::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
