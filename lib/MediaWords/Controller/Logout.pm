package MediaWords::Controller::Logout;
use Moose;
use namespace::autoclean;
use URI::Escape;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

MediaWords::Controller::Logout - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

Logout

=cut

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    my $email = $c->user->username;

    # Clear the user's state
    $c->logout;

    # Send the user to the starting point
    $c->response->redirect( $c->uri_for( '/login' ) . '?email=' . uri_escape( $email ) );
}

=head1 AUTHOR

Linas Valiukas

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
