package Catalyst::Action::MC_REST;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base 'Catalyst::Action::REST';

use Moose;
use namespace::autoclean;


=head1 NAME Catalyst::Action::MC_REST

Media Cloud Rest Action

=head1 DESCRIPTION

Media Cloud specific sub class of Catalyst::Action::REST that forwards all foo_POST methods to
foo_GET.

=cut

=head1 METHODS

=head2 dispatch( $self, $c )

Dispath method using Catalyst::Action::REST after converting foo_POST to foo_GET

=cut

sub dispatch {
    my $self = shift;
    my $c    = shift;

    my $method = uc( $c->req->method );

    $method = 'GET' if ( $method eq 'POST' );

    my $rest_method = $self->name . "_" . $method;

    return $self->SUPER::_dispatch_rest_method( $c, $rest_method );
}

sub get_allowed_methods {
    my ( $self, $controller, $c, $name ) = @_;

    my $methods = $self->SUPER::get_allowed_methods( $controller, $c, $name );

    push( @{ $methods }, 'POST' ) unless ( grep { $_ eq 'POST' } @{ $methods } );

    return $methods;
};

1;
