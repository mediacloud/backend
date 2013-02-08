package MediaWords::Controller::Root;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dumper;
use MediaWords::Util::Config;

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{ namespace } = '';

=head1 NAME

MediaWords::Controller::Root - Root Controller for MediaWords

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=cut

=head2 default

=cut

sub begin : Private
{
    my ( $self, $c ) = @_;

    my $locale = $c->request->param( 'locale' );

    $c->response->headers->push_header( 'Vary' => 'Accept-Language' );    # hmm vary and param?
    $c->languages( $locale ? [ $locale ] : undef );

    #switch to english if locale param is not explicitly specified.
    $c->languages( $locale ? [ $locale ] : [ 'en' ] );
}

=head2 auto
 
Check if there is a user and, if not, forward to login page
 
=cut

# Note that 'auto' runs after 'begin' but before your actions and that
# 'auto's "chain" (all from application path to most specific class are run)
# See the 'Actions' section of 'Catalyst::Manual::Intro' for more info.
sub auto : Private
{
    my ( $self, $c ) = @_;

    # Allow unauthenticated users to reach the login page.  This
    # allows unauthenticated users to reach any action in the Login
    # controller.  To lock it down to a single action, we could use:
    #   if ($c->action eq $c->controller('Login')->action_for('index'))
    # to only allow unauthenticated access to the 'index' action we
    # added above.
    if ( $c->controller eq $c->controller( 'Login' ) )
    {
        return 1;
    }

    # If a user doesn't exist, force login
    if ( !$c->user_exists )
    {

        # Dump a log message to the development server debug output
        $c->log->debug( '***Root::auto User not found, forwarding to /login' );

        # Redirect the user to the login page
        $c->response->redirect( $c->uri_for( '/login' ) );

        # Return 0 to cancel 'post-auto' processing and prevent use of application
        return 0;
    }

    # User found, so return 1 to continue with processing after this 'auto'
    return 1;
}

sub default : Private
{
    my ( $self, $c ) = @_;

    # Redirect to default homepage
    my $config            = MediaWords::Util::Config::get_config;
    my $default_home_page = $config->{ mediawords }->{ default_home_page };
    $c->response->redirect( $c->uri_for( $default_home_page ) );
}

=head2 end

Attempt to render a view, if needed.

=cut 

sub end : ActionClass('RenderView')
{
    my ( $self, $c ) = @_;

    if ( scalar @{ $c->error } )
    {
        $c->stash->{ errors } = [ map { $_ } @{ $c->error } ];

        print STDERR "Handling error:\n";
        print STDERR Dumper( $c->stash->{ errors } );

        my $config = MediaWords::Util::Config::get_config;
        my $always_show_stack_traces = $config->{ mediawords }->{ always_show_stack_traces } eq 'yes';

        if ( $always_show_stack_traces )
        {
            $c->config->{ stacktrace }->{ enable } = 1;
        }

        if ( !( $c->debug() || $always_show_stack_traces ) )
        {
            $c->error( 0 );

            $c->stash->{ template } = 'public_ui/error_page.tt2';

            $c->response->status( 500 );
        }
    }

}

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
