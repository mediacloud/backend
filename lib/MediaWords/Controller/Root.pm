package MediaWords::Controller::Root;
use Modern::Perl "2015";
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

=head2 auto
 
Check if there is a user and, if not, forward to login page
 
=cut

sub default : Private
{
    my ( $self, $c ) = @_;

    # Redirect to default homepage
    my $config            = MediaWords::Util::Config::get_config;
    my $default_home_page = $config->{ mediawords }->{ default_home_page };
    $c->response->redirect( $c->uri_for( $default_home_page ) );
}

sub begin : Private
{
    my ( $self, $c ) = @_;

    my $locale = $c->request->param( 'locale' );

    $c->response->headers->push_header( 'Vary' => 'Accept-Language' );    # hmm vary and param?
    $c->languages( $locale ? [ $locale ] : undef );

    #switch to english if locale param is not explicitly specified.
    $c->languages( $locale ? [ $locale ] : [ 'en' ] );
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

        map { $_ =~ s/at \/.*// } @{ $c->stash->{ errors } };

        my $config                   = MediaWords::Util::Config::get_config;
        my $always_show_stack_traces = $config->{ mediawords }->{ always_show_stack_traces } eq 'yes';

        if ( $always_show_stack_traces )
        {
            $c->config->{ stacktrace }->{ enable } = 1;
        }

        if ( !( $c->debug() || $always_show_stack_traces ) )
        {
            $c->error( 0 );

            $c->stash->{ template } = 'public_ui/error_page.tt2';

            $c->response->status( 500 ) if ( $c->response->status < 400 );
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
